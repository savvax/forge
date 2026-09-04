# forge — отчёт независимой проверки

Аудит проекта по досье `docs/AUDIT.md`. Дата проверки: 4.09.2026.
Проверенное состояние: коммит `87a27b4` (на 1 docs-коммит новее базового `44fcf07`, тег `v1.0.0`;
код и golden между этими коммитами не менялись — `44fcf07` = review-фикстуры, `87a27b4` = сам AUDIT.md).
Рабочее дерево чистое, untracked — только артефакты проверок в `tmp/`, `output/` (вне git).

Окружение: macOS arm64, mise 2026.8.1, Ruby 3.3.12 (`mise.toml` → `ruby = "3.3"`), bundler 4.0.20
(`bundle check` — зависимости удовлетворены), Docker 29.4.0.

**Итог: все проверки из § 3 досье воспроизведены, расхождений с утверждениями AUDIT.md не найдено.
Блокирующих проблем нет.** Замечания — только редакционные (раздел 7).

## 1. Командные проверки (§ 3 досье)

| # | Команда | Ожидание (AUDIT) | Факт | Вердикт |
|---|---|---|---|---|
| 1 | `mise exec -- bundle exec rake ci` | rubocop 0; 216 examples 0 failures; guard:vendor ok; determinism ok (21 files); licenses ok; readme:check ok; exit 0 | rubocop: 102 files, no offenses; 216 examples, 0 failures; coverage line 98.04% / branch 84.54%; guard:vendor ok; determinism ok (21 files); licenses ok (52 gems); readme:check ok (4 commands); exit 0 | ✅ |
| 2 | `bin/forge analyze --spec examples/specs/novapay.yaml` | 5 ролей 0.95/0.90/0.95/0.90/0.85; 3 WARN + 3 INFO; exit 0 | create 0.95, status 0.90, cancel 0.95, webhook 0.90, balance 0.85; Warnings (3), Info (3); exit 0 | ✅ |
| 3 | `bin/forge generate … novapay.yaml --out tmp/out/novapay --force` | Verifying ok (ruby -c ×3, rspec 13 examples, 0 failures); Done: 6 files; exit 0 | `Verifying generated code... ok (ruby -c ×3, rspec 13 examples, 0 failures)`; `Done: 6 files, 3 warnings, 0 unsupported`; exit 0 | ✅ |
| 4 | `bin/forge generate … cardpay.yaml --overrides … --force --strict; echo $?` | 0 (0 WARN) | `Done: 6 files, 0 warnings, 0 unsupported`; exit 0 | ✅ |
| 5 | `bin/forge generate … swiftpay.json --out tmp/out/s --force` | 4 WARN, 3 UNSUPPORTED, 1 pending, exit 0 | `Done: 6 files, 4 warnings, 3 unsupported`; exit 0; сгенерированный spec: `11 examples, 0 failures, 1 pending` | ✅ |
| 6 | `bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo $?` | error circular $ref + hint; 1 | `error: circular $ref: #/components/schemas/A -> … at #/paths/~1payouts/post/requestBody/b/a in …` + `hint: break the cycle…`; exit 1 | ✅ |
| 7 | `bin/forge generate … broken/no_create.yaml …; echo $?` | error no create endpoint + hint; 2 | `error: no create endpoint found in the spec …` + `hint: set endpoints.<operationId>: create (overrides.yml)`; exit 2 | ✅ |
| 8 | `bin/integrate … --lang python; echo $?` | only ruby is supported; 1 | `error: only ruby is supported (got --lang python)`; exit 1 | ✅ |
| 9 | `bin/integrate --spec … --provider novapay` (счастливый путь) | 6 файлов | exit 0; `output/novapay/`: service, spec, helper, INTEGRATION.md, fixtures.json, mock_server.rb, report.txt | ✅ |
| 10 | `bin/e2e examples/specs/novapay.yaml` | operation approved ✓; exit 0 | `operation approved ✓ (novapay)`; exit 0 (мок-сервер, сервис и приёмник webhook отработали целиком) | ✅ |
| 11 | `bundle exec rake real` | 7 спек, analyze exit 0 для всех, 15 examples | 7/7 exit 0 (stripe 10 WARN/1 UNSUP; adyen_payout 46/1; adyen_transfers 118/2; paypal 10/2; paystack 10/0; square 7/9; plaid 61/0); 15 examples, 0 failures; exit 0. Спеки уже были скачаны — таск отработал по ветке `skip` (см. § 7.6) | ✅ |
| 12 | `docker build -t forge . && docker run …` | generate в контейнере, 6 файлов | build exit 0; run exit 0; `tmp/d/` — 6 файлов | ✅ |
| 13 | `UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb && git diff --stat spec/golden` | пустой diff = golden актуальны | 5 examples, 0 failures; `git diff --stat spec/golden` пуст. Нюанс: сам rspec-процесс возвращает exit 2 из-за гейта SimpleCov при одиночном запуске (см. § 7.1) — критерием служит пустой diff, он выполнен | ✅ |

## 2. Жёсткие ограничения (§ 1.3, C1–C4)

| # | Ограничение | Проверка | Вердикт |
|---|---|---|---|
| C1 | Весь код на Ruby | `bin/{forge,integrate,e2e,demo}` — `#!/usr/bin/env ruby`, `file` → «Ruby script»; логики на shell/Python нет | ✅ |
| C2 | Только open-source зависимости | `rake licenses`: сверка с `ALLOWED_LICENSES`, `licenses ok (52 gems)` | ✅ |
| C3 | Никаких сетевых вызовов при анализе/генерации; детерминизм | В конвейере analyze/generate сетевого кода нет; детерминизм — `determinism ok (21 files)` (два прогона, одинаковые файлы). Сетевой код существует только вне конвейера: `Rakefile` (`real:fetch`), `bin/e2e` + шаблон мока (localhost), и обёртка Faraday в `lib/provider/http_client.rb` — runtime-код сгенерированных сервисов, при генерации не вызывается (см. § 7.2) | ✅ |
| C4 | Знание о провайдере не живёт в `lib/` | `rake guard:vendor` в составе `rake ci` — ok; независимый grep по `lib/` (novapay\|cardpay\|swiftpay\|stripe\|adyen\|paystack\|paypal) — пусто | ✅ |

## 3. Стандарты кода (§ 1.4)

| Требование | Факт | Вердикт |
|---|---|---|
| `# frozen_string_literal: true` | 61/61 файлов `lib/**/*.rb` | ✅ |
| Ruby 3.3 | `TargetRubyVersion: 3.3`; runtime 3.3.12 | ✅ |
| Без метапрограммирования | `define_method`/`eval`/`instance_eval`/`class_eval` в `lib/` нет; единственный динамический вызов — `public_send` по фиксированному списку ключей (`overrides_apply.rb:34`) | ✅ |
| Файлы < 200 строк | макс. файл `lib/` — 177 строк (`plan/fixtures.rb`); исключение — шаблон `templates/service.rb.erb` (234 строки, не Ruby-файл, вне поля rubocop; см. § 7.4) | ✅ |
| Методы < 20 строк | `Metrics/MethodLength: Max: 20` в `.rubocop.yml`; rubocop — 0 offenses | ✅ |
| Коды ошибок | Спект: SpecError → 1, GenerationError → 2, VerificationError → 3, `--strict` → 4. Проверено живьём: cyclic_ref → 1, no_create → 2, `--lang python` → 1. Коды 3/4 покрыты спеками (`spec/forge_spec.rb:25`, `spec/cli_spec.rb:114`, `generate_command_spec.rb:22`) | ✅ |
| Формат сообщения `<что> at <pointer> in <file>` + `hint:` | подтверждён живыми прогонами (№ 6–8 таблицы 1) | ✅ |
| Coverage: line ≥ 90 %, branch ≥ 75 %, по файлу ≥ 70 % | `SimpleCov.minimum_coverage line: 90, branch: 75`, `minimum_coverage_by_file 70`; полный прогон: 98.04 % / 84.54 % | ✅ |
| Rubocop 0 | 102 files, no offenses | ✅ |
| Golden байт-в-байт | git diff пуст после UPDATE_GOLDEN; золотой `novapay_service.rb` побайтово идентичен целевому тексту `docs/OUTPUT_FORMAT.md` § 1 (сверено скриптом, байтовые размеры равны) | ✅ |

## 4. Уточнения организаторов (§ 1.2) — точечная сверка

| # | Утверждение | Факт | Вердикт |
|---|---|---|---|
| Q1 | `request_method` — логический тип действия | `STATUS_METHODS = %w[status check]` в золотом сервисе, делегирование `fetch_status` | ✅ |
| Q2 | WARN + TODO + `overrides.yml` | каждый WARN в отчётах несёт `hint:` с ключом overrides | ✅ |
| Q5 | Копейки ×100, `bank_code` при `type=sbp`, HMAC-SHA256(raw body) → hex | `AMOUNT_MULTIPLIER = 100` (golden:43), `when 'sbp' then base.merge(bank_code: …, bank_name: …)` (golden:149), `verify_signature!` + HMAC-SHA256 hex (golden:176–177) | ✅ |
| Q6 | Секреты «заполнить вручную» | `INTEGRATION.md`: «Заполнить вручную: `credentials.api_key`, `credentials.callback_secret`» | ✅ |
| Q8 | Своя заглушка `Provider::BaseService` | `lib/provider/{base_service,errors,result,operation,memory_operations,http_client}.rb` | ✅ |

## 5. Осознанные отклонения (§ 4 досье) — сверка «сделано так, как задекларировано»

| # | Отклонение | Проверка | Вердикт |
|---|---|---|---|
| 1 | SwiftPay cancel DELETE → 0.85 без WARN | `rules/endpoint_roles.yml`: `method_delete: 0.20`; в отчёте cancel 0.85 без WARN | ✅ |
| 2 | `OperationPlan.endpoint` | `lib/forge/plan/integration_plan.rb:12` — поле `:endpoint` | ✅ |
| 3 | Reference-тест через `payout_requisite` | `spec/reference_spec.rb:18`: `payload.dig('error', 'code')`, `operation.payout_requisite`, `'sbp'`, `bank_code`, `bank_name`, `'phone'` | ✅ |
| 4 | `bank_name` в варианте `sbp` | golden:149 | ✅ |
| 6 | cyclic `SpecError` из анализатора | сообщение об ошибке содержит указатель внутрь `requestBody` (анализатор, не загрузчик), exit 1 тот же | ✅ |
| 7 | `Rules.load` от корня проекта | `lib/forge/rules.rb:8`: `DEFAULT_DIR = File.expand_path('../../rules', __dir__)` | ✅ |
| 8 | Thor в `lib/forge/cli.rb` | так и есть | ✅ |
| 9 | `Rack::MockRequest` вместо гема rack-test | `spec/renderers/mock_server_spec.rb`; `rack-test` в Gemfile отсутствует | ✅ |
| 10 | `report.txt` — относительные пути | секция Output: `./novapay_service.rb` и т.д.; stdout — полные пути | ✅ |
| 11 | `fields.<path>.variant` не реализован | `lib/forge/analyzers/fields.rb:45` — hint `…(overrides.yml, not implemented yet)` | ✅ |

Отклонения 5 (тело ⊆ fixtures) и полнота паков — покрыты reference- и golden-тестами (зелёные), отдельно руками не воспроизводились.

## 6. Известные ограничения (§ 5) и вне проверенного состояния (§ 6)

- `media_type_form` отсутствует в `lib/` и `rules/` — WARN действительно не реализован; create-payout в
  реальной спеке Stripe имеет `application/x-www-form-urlencoded`, тело уйдёт как JSON. Ограничение
  задекларировано честно.
- § 6 подтверждён: remote `origin = github.com/savvax/forge.git`, тег `v1.0.0` существует только
  локально (`git ls-remote --tags origin` пуст); `[x]` в `AGENT_TASKS.md`/`docs/AGENT_TASKS.md` — 0;
  job `real-specs` в CI — `workflow_dispatch`/`schedule` с `continue-on-error: true`.

## 7. Наблюдения (не блокирующие)

1. **Команда UPDATE_GOLDEN из § 3 возвращает exit 2 даже на актуальных golden.** SimpleCov-гейт
   (90 %/75 %) применяется к каждому запуску rspec, а одиночный `spec/golden_spec.rb` покрывает мало.
   Сами golden-тесты зелёные, diff пуст. Проверяющему: критерий — пустой `git diff`, не код выхода;
   либо запускать полный набор (`rake ci`).
2. **Формулировка C3 «единственный сетевой код — `rake real:fetch` и мок» неполна**: есть ещё runtime-обёртка
   Faraday `lib/provider/http_client.rb` (используется сгенерированными сервисами и e2e против локального
   мока). Само ограничение («нет сети при анализе и генерации») соблюдается — при конвейере Faraday не вызывается.
3. **Путь к mise-файлу**: AUDIT § 3 пишет `.mise.toml`, в репозитории файл называется `mise.toml` (без точки).
4. **`templates/service.rb.erb` — 234 строки**: формально превышает планку «файлы < 200 строк», если
   применять её к ERB-шаблонам; rubocop inspectирует только `.rb`. Кандидат на разбиение при полировке (T17).
5. **База сверки**: AUDIT.md заявлен «актуально на `44fcf07`», проверка выполнена на `87a27b4` — единственный
   более поздний коммит и есть сам AUDIT.md; на результаты не влияет.
6. **`rake real` при наличии скачанных спек** не выполняет сетевую загрузку (ветка `skip`); сетевой путь
   `real:fetch` в этом прогоне не переупражнялся (в досье заявлен как «скачивает 7 спек»).

## 8. Вывод

Утверждения `docs/AUDIT.md` воспроизводимы: все 13 командных проверок § 3 дали заявленный результат,
жёсткие ограничения C1–C4 и стандарты кода § 1.4 соблюдены, задекларированные отклонения § 4
соответствуют коду, известные ограничения § 5 подтверждены. Проект соответствует заявленному
состоянию `v1.0.0`. Рекомендации ограничиваются редакционными правками AUDIT.md (наблюдения 1–3)
и опциональным разбиением сервиса-шаблона (наблюдение 4).
