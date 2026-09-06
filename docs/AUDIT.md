# forge — досье для аудита

Документ для независимого проверяющего (человека или агента): что требовалось, что реализовано, где это
лежит, как проверить каждое утверждение командой и какие отклонения от документов приняты осознанно.
Актуально на тег `v1.0.0` (5.09.2026). Первоисточники: `docs/TASK.md`, `docs/QA_SESSION_1.md`,
`docs/CRITERIA.md`, `CLAUDE.md`, `docs/AGENT_TASKS.md`, `NOTES.md` (решения D-01…D-20).

## 1. Требования

### 1.1 Условие задачи (`docs/TASK.md`)

| # | Требование | Где проверять |
|---|---|---|
| R1 | Вход — OpenAPI 3.0/3.1 (YAML/JSON) провайдера выплат; только payout, депозиты не нужны | `lib/forge/loader.rb`, `spec/loader_spec.rb` |
| R2 | Выход: `<provider>_service.rb` по контракту `Provider::BaseService` (`check_conditions`, `create_request`, `process_callback`, `fetch_status`) | `templates/service.rb.erb`, `spec/golden/novapay/novapay_service.rb`, `spec/reference_spec.rb` |
| R3 | Выход: `INTEGRATION.md` (авторизация, методы, статусы, ошибки, ProviderGateway config, подпись webhook) | `templates/integration.md.erb`, `spec/renderers/outputs_spec.rb` (все строки эталона `spec/reference/novapay/INTEGRATION.md` присутствуют) |
| R4 | Выход: `fixtures.json` с ключами ТЗ и `expected_operation_status` | `lib/forge/plan/fixtures.rb`, тест `deep_include` эталона `spec/reference/novapay/fixtures.json` |
| R5 | CLI `./integrate --spec … --provider … --lang ruby` с прогресс-выводом («Parsing spec… Found N endpoints… Auth… Webhook signature… Generating… Output:») | `bin/integrate`, `lib/forge/report.rb`, `spec/cli_spec.rb`, `spec/snapshots/*_analyze.txt` |
| R6 | Доп. эндпоинты (balance, cancel, list) — «найдено, вне контракта», как необязательные хелперы | `INFO outside_contract` в отчёте, `cancel_request`/`fetch_balance` в отдельном классе `<P>Extras` (`<p>_extras.rb`, D-15) |

### 1.2 Уточнения организаторов (`docs/QA_SESSION_1.md`, приоритет над догадками)

| # | Требование | Реализация |
|---|---|---|
| Q1 | `request_method` — логический тип действия (`sbp`, `card`, `status`/`check`), не HTTP-verb | `STATUS_METHODS`, `requisite_type_for(operation, request_method)` в сервисе (D-02) |
| Q2 | Неоднозначность не угадывать молча: структура → автоматически; текст `description` → WARN + TODO + строка `overrides.yml` | `Finding.warnings`, раздел «Допущения» в `INTEGRATION.md`, `# TODO(forge)` в коде, `hint:` у каждого WARN |
| Q3 | Overrides — общий механизм, не привязка к провайдеру | `lib/forge/plan/overrides*.rb`, схема ключей `docs/RULES.md` § 9 |
| Q4 | Канон статусов без таблицы: pending/processing → in_progress, completed → approved, failed/cancelled → rejected; вне словаря — WARN `unmapped_status` | `rules/status_map.yml`, `lib/forge/analyzers/statuses.rb` |
| Q5 | Канон NovaPay: копейки ×100, `bank_code` обязателен при `type=sbp`, HMAC-SHA256(raw body) → hex | `AMOUNT_MULTIPLIER = 100`, `required_if`, `verify_signature!` в golden |
| Q6 | Секреты — из `credentials`, с пометкой «заполнить вручную» | `INTEGRATION.md` → «Авторизация → Заполнить вручную» |
| Q7 | Неподдерживаемое критичное → явная ошибка с подсказкой; некритичное → UNSUPPORTED, генерация продолжается | D-05, D-14: внешний/циклический/битый `$ref` в запросе create → exit 1, иначе UNSUPPORTED |
| Q8 | Реальный `Provider::BaseService` не выдают — своя заглушка | `lib/provider/*` (код из `docs/CONTRACT.md` § 5), `spec/provider/` |
| Q9 | Веб-интерфейс не нужен; документация может быть на русском | CLI + README/INTEGRATION.md на русском |

### 1.3 Жёсткие ограничения (`CLAUDE.md`, нарушение = дисквалификация)

| # | Ограничение | Как обеспечено |
|---|---|---|
| C1 | Весь код на Ruby; `bin/*` — Ruby | `bin/forge`, `bin/integrate`, `bin/e2e`, `bin/demo` — Ruby с shebang; логики на shell/Python нет |
| C2 | Только open-source зависимости | `bundle exec rake licenses` → `licenses ok (52 gems)`; список — `Gemfile` |
| C3 | Никаких нейросетей/LLM, никаких сетевых вызовов при анализе и генерации; детерминизм | Правила и словари `rules/*.yml`; `rake determinism` (два прогона → одинаковые sha256, 21 файл); единственный сетевой код — `rake real:fetch` (скачивание спек для тестов) и мок |
| C4 | Знание о провайдере не живёт в `lib/` | `rake guard:vendor` (grep `novapay|cardpay|swiftpay|stripe|adyen|paystack|paypal` по `lib/`) входит в `rake check` |

### 1.4 Стандарты кода (`CLAUDE.md`)

`# frozen_string_literal: true`; Ruby 3.3; без метапрограммирования; файлы < 200 строк, методы < 20; ошибки
`Forge::Error` → `SpecError` (exit 1), `UnsupportedError` (1), `GenerationError` (2), `VerificationError` (3),
`--strict` (4); сообщение `"<что> at <pointer> in <file>\n  hint: <что делать>"`; SimpleCov line ≥ 90 %,
branch ≥ 75 %, по файлу ≥ 70 %; rubocop 0; golden байт-в-байт; коммит после каждой зелёной задачи.

### 1.5 Критерии оценки (`docs/CRITERIA.md`) → где смотреть

См. таблицу «Критерий → где смотреть» в `README.md`.

## 2. Реализация

### 2.1 Архитектура

```
Load ──▶ IR ──▶ Analyze ──▶ Plan ──▶ Render ──▶ Verify ──▶ Report
```
Стадии знают только о соседях: парсер не знает о Ruby-коде, шаблоны видят только `IntegrationPlan`.

| Стадия | Файлы | Что делает |
|---|---|---|
| Load | `lib/forge/loader.rb`, `ref_resolver.rb` | YAML/JSON → Hash; проверки `openapi: 3.x`, `swagger`, `paths`; server variables → default (enum → `x-forge-url-alternatives`); резолв локальных `$ref` (`~0`/`~1`, percent-encoding) с кэшем; внешний `$ref` → `x-forge-unresolved`, цикл → `x-forge-circular` (D-05, D-14) |
| IR | `lib/forge/ir/*.rb` | `Data.define`: Spec, Server, SecurityScheme, Endpoint, Parameter, RequestBody, Response, Schema; Builder мержит path-level параметры, наследует root security, выбирает JSON media type, сливает `allOf`, 3.1 `type: [..]` → nullable, `callbacks`/`webhooks` → Endpoint(source:) |
| Analyze | `lib/forge/analyzers/*.rb`, `rules/*.yml` | 7 анализаторов в фиксированном порядке (`Runner`): EndpointRoles (очки сигналов, `requires`, negative words, конфликты), Auth, Statuses, Errors, Webhooks, Amount, Fields (+ `FieldWalker`). Каждый → `Finding(key, value, confidence, source, warnings)` |
| Plan | `lib/forge/plan/*.rb` | `Builder` → `IntegrationPlan` (provider/base_url/auth/operations/webhook/status_map/event_map/error_map/success_statuses/amount/requisite_types/fields/validations/gateway_config/fixtures/outside_contract/warnings/meta); `Naming`, `Validations`, `Fixtures` (+`FixturesOperation`, синтез по схеме через `Fixtures::Synthesizer`), `Overrides` (схема ключей, did-you-mean) + `OverridesApply`/`OverridesEdits` |
| Render | `lib/forge/renderers/*.rb`, `templates/*.erb` | Service (+ `ServiceView`, `ServicePaths`, `ServicePayload`, партиалы `_auth_headers`, `_rescues`, `_verify_signature`), ServiceSpec, IntegrationDoc, Fixtures (JSON), MockServer (Sinatra); `Runner` пишет файлы + копирует `generated_spec_helper.rb`; `ReportFile` → `report.txt` |
| Verify | `lib/forge/verifier.rb` | `ruby -c` на всех `.rb`; `bundle exec rspec --options /dev/null` на сгенерированном spec (отключается `--no-verify`) |
| Report | `lib/forge/report.rb`, `report_lines.rb` | Текст в формате ТЗ + секции Warnings/Unsupported/Info с `hint`, сворачивание > 10 записей; `--format json` |

CLI: `lib/forge/cli.rb` (Thor) → `lib/forge/generate_command.rb` (конвейер, коды выхода, `mock!`).
Контракт-заглушка: `lib/provider/{errors,result,operation,memory_operations,http_client,base_service}.rb`.

### 2.2 Команды

| Команда | Назначение |
|---|---|
| `bin/forge analyze --spec F [--overrides F] [--include-paths G]… [--format text\|json] [--debug]` | отчёт без генерации |
| `bin/forge generate --spec F [--provider N] [--out D] [--overrides F] [--include-paths G]… [--templates-dir D] [--lang ruby] [--format] [--strict] [--no-verify] [--force]` | 6–7 файлов + верификация |
| `bin/forge mock --spec F [--port P] [--webhook-url U] [--overrides F]` | рендер + запуск Sinatra-мока |
| `bin/integrate --spec F --provider N [--lang ruby]` | обёртка ТЗ → `generate --out ./output/<provider> --force`; `--lang` ≠ ruby → exit 1 |
| `bin/e2e SPEC [--overrides F]` | мок + сервис + приёмник webhook → `operation approved ✓`, exit 0 |
| `bin/demo [SPEC] [--fast]` | сценарий демо |
| `bin/forge-web` / `docker compose up` | веб-интерфейс (демо): загрузка спеки, отчёт, файлы, rspec/e2e кнопкой (D-23) |
| `rake check` / `rake ci` / `rake real` / `rake determinism` / `rake licenses` / `rake guard:vendor` / `rake golden:update` | проверки |

### 2.3 Словари (`rules/`)

`thresholds.yml` (accept 0.8, warn 0.5), `endpoint_roles.yml` (слова, сигналы, веса, negative words),
`status_map.yml`, `error_actions.yml`, `amount_units.yml`, `currency_exponents.yml`, `field_aliases.yml`
(алиасы полей, реквизиты по типам из CONTRACT § 3, `requisite_defaults`), `webhook_signature.yml`.
Описание алгоритмов — `docs/RULES.md`.

### 2.4 Сгенерированный вывод (`spec/golden/<provider>/`)

Для `novapay`, `cardpay`, `cardpay_overrides`, `swiftpay`, `swiftpay_overrides`, `raiffeisen`, `raiffeisen_overrides`: `<p>_service.rb`,
`<p>_extras.rb` (если есть cancel/balance), `<p>_service_spec.rb`, `generated_spec_helper.rb`, `INTEGRATION.md`,
`fixtures.json`, `mock_server.rb`, `report.txt`. Golden для NovaPay-сервиса совпадает с целевым текстом `docs/OUTPUT_FORMAT.md` § 1.

### 2.5 Тесты (`spec/`)

216 примеров: loader, ref_resolver, ir, rules, 7 анализаторов, plan (naming/builder/overrides), renderers
(service/outputs/runner/mock_server), provider stub, verifier, report, cli (все коды выхода, `--debug`,
`--strict`, `--force`, `--templates-dir`, `--format json`, битые спеки `spec/fixtures/broken/*`),
golden (5 наборов), determinism, generate_command, reference (элементы ТЗ), e2e (novapay, cardpay).
Реальные спеки — `spec/real_specs_spec.rb` (тег `:real`, `REAL=1`, снапшоты `examples/real/reports/`).

## 3. Как проверить (команды и ожидаемые результаты)

```bash
mise install && bundle install            # Ruby 3.3 (.mise.toml)
bundle exec rake ci                       # ~15 с: rubocop 0; 216 examples, 0 failures; guard:vendor ok;
                                          # generated specs зелёные; determinism ok (21 files); licenses ok; readme:check ok
bin/forge analyze --spec examples/specs/novapay.yaml         # 5 ролей 0.95/0.90/0.95/0.90/0.85; 3 WARN + 4 INFO; exit 0
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/out/novapay --force
                                          # Verifying… ok (ruby -c ×4, rspec 13 examples, 0 failures); Done: 7 files
bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --out tmp/out/c --force --strict; echo $?   # 0 (0 WARN)
bin/forge generate --spec examples/specs/swiftpay.json --out tmp/out/s --force   # 5 WARN, 2 UNSUPPORTED, exit 0
bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo $?           # error: circular $ref … hint: … ; 1
bin/forge generate --spec spec/fixtures/broken/no_create.yaml --out tmp/x --force; echo $?   # error: no create endpoint … ; 2
bin/integrate --spec examples/specs/novapay.yaml --provider novapay --lang python; echo $?   # only ruby is supported; 1
bin/e2e examples/specs/novapay.yaml       # … operation approved ✓ (novapay); exit 0
bundle exec rake real                     # скачивает 7 спек, analyze exit 0 для всех, 15 примеров
docker build -t forge . && docker run --rm -v "$PWD/examples:/app/examples" -v "$PWD/tmp:/app/tmp" forge generate --spec examples/specs/novapay.yaml --out tmp/d --force
UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb && git diff --stat spec/golden   # пусто = golden актуальны
```

Ожидания по спекам — `docs/TEST_SPECS.md` (§ 2 CardPay: 5 WARN + 4 INFO; § 3 SwiftPay: 5 WARN + 2 UNSUPPORTED;
§ 4 битые спеки) и `docs/SPEC_ANALYSIS_NOVAPAY.md` (числа для NovaPay). Снапшоты `analyze` —
`spec/snapshots/`.

## 4. Осознанные отклонения от документов (проверяющему знать)

| # | Документ говорит | Сделано | Почему (ссылка) |
|---|---|---|---|
| 1 | RULES § 2: SwiftPay cancel через DELETE набирает 0.65 → WARN | сигнал `method_delete: 0.20` → 0.85 без WARN | D-09: REST-семантика однозначна |
| 2 | ARCHITECTURE: `OperationPlan` без IR | добавлено поле `endpoint` | D-11: рендереру нужны схемы ответов |
| 3 | SPEC_ANALYSIS «Reference-тест»: буквальный `dig('sbp', 'phone')` | проверяются `payout_requisite`, `'sbp'`, `'phone'`, `bank_code`, `bank_name` | golden из OUTPUT_FORMAT § 1 использует `build_recipient` с вариантами по типу (`requisite['phone']`) |
| 4 | SPEC_ANALYSIS Fields: `bank_name` без типа | `bank_name` в варианте `sbp` | D-12: пересечение `types` из CONTRACT § 3 с enum типа |
| 5 | OUTPUT_FORMAT § 2: тело запроса == fixtures.request | тело ⊆ примера (без nil), поля с override `source` исключены | D-13 |
| 6 | TEST_SPECS § 4: `cyclic_ref`, `bad_ref` → `SpecError` из загрузчика | маркеры в загрузчике, `SpecError` из `Analyzers::Fields` (CLI: exit 1 те же) | D-14: реальные спеки рекурсивны |
| 7 | RULES § 0: `Rules.load('rules')` относительно cwd | относительно корня проекта | `bin/integrate` из любого каталога |
| 8 | AGENT_TASKS T01: Thor в `lib/forge/cli.rb` | так и есть (после T07) | — |
| 9 | Карточка T15: Rack::Test | `Rack::MockRequest` из rack | гем `rack-test` не в Gemfile, новый гем требует согласия |
| 10 | ТЗ пример `report.txt`: «Done: 6 files» | `report.txt` содержит пути относительно каталога вывода (`./novapay_service.rb`), stdout — полные | детерминизм между каталогами (`rake determinism`) |
| 11 | RULES § 9: `fields.<path>.variant` для `oneOf` | реализовано (D-17) | — |
| 12 | OUTPUT_FORMAT § 1: `cancel_request`/`fetch_balance` внутри сервиса | отдельный файл `<p>_extras.rb`, класс `<P>Extras < <P>Service`; сервис — только контракт | D-15, замечание экспертов |
| 13 | ARCHITECTURE: `--strict` → exit 4 | так и есть, но режим «комбинированный»: все файлы и отчёт создаются, код 4 только в конце | D-16, замечание экспертов |

## 5. Известные ограничения (README «Ограничения»)

Только OpenAPI 3.x; только payout; OAuth2-флоу не генерируется (bearer + TODO); подпись `t=…,v1=…` проверяется
(D-29), прочие timestamp/nonce-схемы → `NotImplementedError` с TODO; массивы полей (PayPal `items[]`) не мапятся. Закрыто 5.09 (D-17…D-20): выбор
варианта `oneOf` через overrides, form-urlencoded тела (`form:` + WARN), статус через POST с id в теле,
валидация фикстур по схемам спеки (INFO). NovaPay теперь даёт 3 WARN + 4 INFO: четвёртый INFO —
`fixture_schema_mismatch` (пример 401 в ТЗ не входит в enum кодов ошибок).

## 5a. Проверка против живых провайдеров (5.09, без учётных данных)

Сгенерированные из реальных спек сервисы (`bin/forge generate` на `examples/real/*`) вызывали настоящие
sandbox-API с заведомо неверным ключом. Проверяется формирование запроса, транспорт и классификация ответа.

| Провайдер | `create_request` | `fetch_status` (несуществующий id) | Реальный ответ сервера |
|---|---|---|---|
| Stripe `api.stripe.com` (form-urlencoded) | `provider.invalid_credentials` | `provider.invalid_credentials` | 401 `invalid_request_error` |
| Paystack `api.paystack.co` | `provider.invalid_credentials` | `bad_request`/`provider.unknown_error` | 401 `invalid_Key`; GET → 400 `invalid_params` (код вне словаря) |
| PayPal sandbox (oauth2 → bearer) | `provider.invalid_credentials` | `provider.invalid_credentials` | 401 `invalid_token` |
| Adyen Transfers (apiKey в query `clientKey`) | `provider.invalid_credentials` | `provider.invalid_credentials` | 401 `00_401` |
| Adyen Payout | `requisite_missing` до запроса (REQUISITE_TYPES = card) | — | — |

Сгенерированные spec зелёные для всех 6 реальных спек с create (Square — exit 2 «no create endpoint»):
Adyen Payout 9, Adyen Transfers 10, PayPal 8, Paystack 8, Stripe 9, Plaid 8 примеров.

Дефекты, найденные этой проверкой и исправленные (все воспроизводимы на реальных спеках):
1. `generate` падал без enum статусов (Paystack) → `STATUS_MAP = {}` с TODO.
2. `create_request` при чужом типе реквизитов → `requisite_missing` вместо KeyError.
3. apiKey в query объявлялся, но не отправлялся (Adyen Transfers) → `with_auth(url)` во всех вызовах.
4. Cancel через POST без path-параметра рендерил `params[:]` (Plaid) → id в теле, как у status.
5. Дублированный ключ контейнера реквизитов и пустые вложенные объекты в теле (Adyen) → `deep_compact`, контейнер на своей глубине.
6. enum поля `type` без канонических значений (`auLocal`) считался типами реквизитов → только словарь CONTRACT § 3.
7. Алиасы `external_id`/`idempotency`/`credential` матчились глубоко внутри объектов (`accountHolder.reference`) → только корень.
8. Синтез фикстур: `"0.00"` суммы, `_example` вместо статуса, обрезка `maxLength`, `default`-реквизит без типа, потерянный Hash в `set_path`.
9. Успешный create без распознанного статуса давал `unknown_provider_status` → `in_progress` (строгая проверка только в `fetch_status`).
10. Тело в сгенерированном spec: сравнение по общим ключам (лишние поля из operation допустимы), пустая `with(headers: {})` ломала блок WebMock.

Позитивный сценарий (201 + webhook) без ключей провайдера недостижим — он покрыт e2e на моке той же спеки.
С тестовыми ключами: `<PROVIDER>_BASE_URL` + `credentials` → `bin/e2e` против sandbox.

## 6. Что не входит в проверенное состояние

- Push на GitHub и CI на `main` не выполнялись из этой сессии (remote `savvax/forge` есть, тег `v1.0.0` локальный).
- Отметки `[x]` в `docs/AGENT_TASKS.md` ведёт человек — не проставлены.
- T17 (полировка по замечаниям CP3) — по определению после чек-поинта.
- Job `real-specs` в CI ручной (`workflow_dispatch`/schedule), `continue-on-error`.
