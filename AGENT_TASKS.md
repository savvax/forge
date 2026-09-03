# Бэклог задач для кодовых агентов

Каждая карточка — одна сессия агента: один модуль (или связка), его тесты, DoD. Запуск: `/task Txx`
(см. `.claude/commands/task.md`) или промпт из `docs/agents/ROLES.md`. Порядок и волны параллелизма —
там же. Отметки `[ ]` ведёт человек. **Баллы** — какие критерии из `docs/CRITERIA.md` закрывает карточка
(Э — эксперты, Ж — техжюри). Подраздел «Остаток» агент заполняет, если не закончил.

---

## M0 — Foundation

### [ ] T01 · Каркас проекта · Core · волна 0
**Читать:** `docs/ARCHITECTURE.md` (структура, CLI), `docs/PROCESS.md` § 5.
**Владеет:** всё в корне, `bin/`, `lib/forge.rb`, `lib/forge/{version,errors}.rb`, `spec/spec_helper.rb`, `spec/support/`.
**Сделать:** положить из комплекта `Gemfile`, `.rubocop.yml`, `.rspec`, `Rakefile`, `Dockerfile`,
`.github/workflows/ci.yml`, `.gitignore`, `.editorconfig`, `spec/spec_helper.rb`; `bundle install`
(при конфликте версий — ослабить `~>` и записать в NOTES); `lib/forge.rb`, `lib/forge/version.rb`
(`'1.0.0'`), `lib/forge/errors.rb` (4 класса с `pointer:`, `hint:`, `file:`), `bin/forge` (Thor, команды
`analyze`/`generate`/`mock`/`version`, первые три печатают `not implemented` и exit 2), `bin/integrate`
(парсит `--spec --provider --lang`, вызывает `bin/forge generate --out ./output`), `spec/support/cli_runner.rb`,
`spec/support/spec_builder.rb` (скелет), `spec/forge_spec.rb` (VERSION, ошибки несут pointer/hint).
Rake-задачи `check`, `ci` (пока = check), `guard:vendor` (grep в `lib/` по `novapay|cardpay|swiftpay|X-NovaPay` → fail).
**Тесты:** `Forge::VERSION == '1.0.0'`; `Forge::SpecError.new('x', pointer: '#/a', hint: 'h').message` содержит `#/a`;
`bin/forge version` печатает версию; `bin/forge help` показывает 4 команды; `bin/integrate --lang python` → exit 1 «only ruby is supported».
**DoD:** `bundle exec rake check` зелёный (SimpleCov на этом этапе ≥ 90 % тривиально); `docker build .` проходит;
`docker run --rm forge help` показывает команды; CI-workflow валиден (job `lint`, `test`).
**Баллы:** база (Э6, Ж7).

---

## M1 — Analyze

### [ ] T02 · Loader и RefResolver · Core · волна 1 (∥ T03)
**Читать:** `docs/ARCHITECTURE.md` → Load; `docs/TEST_SPECS.md` § 4; `docs/SPEC_ANALYSIS_NOVAPAY.md` → Load/IR.
**Владеет:** `lib/forge/loader.rb`, `lib/forge/ref_resolver.rb`, `spec/loader_spec.rb`, `spec/ref_resolver_spec.rb`.
**Сделать:** загрузка YAML/JSON/авто; проверки (пустой, не объект, `swagger`, `openapi`, `paths`); server
variables; резолв локальных `$ref` с `~0`/`~1`; `x-forge-ref-name`; цикл → `SpecError` с цепочкой; внешний
`$ref` → `x-forge-unresolved` (не падать здесь — см. D-05); каждая ошибка с `file:` и `pointer:`.
**Тесты:** каждый файл `spec/fixtures/broken/*` (кроме `no_create`) → класс ошибки и подстрока из таблицы
TEST_SPECS § 4; `Loader.load('examples/specs/novapay.yaml')` → нет ключа `$ref` нигде (рекурсивный обход),
`x-forge-ref-name == 'Recipient'` у схемы recipient; `swiftpay.json` → `servers[0].url == 'https://sandbox.swiftpay.example/api'`;
pointer `#/paths/~1transfer/post/requestBody` резолвится (литеральная мини-спека); внешний ref в balance
не бросает, оставляет `x-forge-unresolved`.
**DoD:** три спеки из `examples/specs/` загружаются; 9 битых дают ожидаемые ошибки.
**Баллы:** Э6 (4), Ж7 (3).

### [ ] T03 · IR и Builder · Core-2 · волна 1 (∥ T02; работать на литеральных Hash, затем на выходе Loader)
**Читать:** `docs/ARCHITECTURE.md` → IR; `docs/SPEC_ANALYSIS_NOVAPAY.md` → Load/IR.
**Владеет:** `lib/forge/ir/*.rb`, `spec/ir/`.
**Сделать:** `Data.define`-структуры; `IR::Builder.build(hash, source_path:)`: path-level parameters мержатся;
security по умолчанию; `security: []`; `examples`+`example` → один Hash; media type приоритет json →
`+json` → первый; `callbacks` и top-level `webhooks` → `Endpoint(source:)`; 3.1 массив типов; `allOf`
слияние; `oneOf`/`anyOf` как есть; `multiple_of`; `unresolved_ref`.
**Тесты:** novapay — 5 эндпоинтов; у `POST /payouts` параметр `Idempotency-Key`; 8 ответов; `Recipient`
`pattern`; `amount.minimum == 100000`; у webhook `security == []`; `Retry-After` в headers ответа 429.
cardpay — у `createTransfer` есть `callbacks` → `Endpoint(source: :callbacks)` с header `X-Signature`; root
security унаследован (`[{'bearerAuth' => []}]`). swiftpay — `webhooks.size == 1`; схема запроса после `allOf`
содержит `reference`, `amount`, `beneficiary`, `purpose`; `purpose.nullable == true`; `beneficiary.one_of.size == 2`;
`DELETE` эндпоинт есть; ответ 422 `media_type == 'application/problem+json'`.
**DoD:** `IR::Builder.build(Loader.load(f)).endpoints.size` = 5 / 3 / 4 для трёх спек.
**Баллы:** Э1 (8), Ж1 (5+5).

### [ ] T04 · Rules, Analyzers::Base, EndpointRoles · Analyzers · волна 2
**Читать:** `docs/RULES.md` § 0–2; `docs/SPEC_ANALYSIS_NOVAPAY.md` → EndpointRoles; `docs/TEST_SPECS.md` § 2–3 (роли).
**Владеет:** `rules/thresholds.yml`, `rules/endpoint_roles.yml`, `lib/forge/rules.rb`, `lib/forge/analyzers/{base,endpoint_roles}.rb`, `spec/analyzers/endpoint_roles_spec.rb`, `spec/rules/`, `spec/support/finding_matchers.rb`.
**Сделать:** `Finding`, `Warning`, нормализация слов (camelCase, `-`, `.`), подсчёт очков по словарю,
`requires`, `negative_words`, конфликт ролей, `include_paths` (glob через `File.fnmatch`).
**Тесты:** novapay — 5 ролей с confidence 0.95/0.90/0.95/0.90/0.85; cardpay — create 0.95, status 0.90,
`listTransfers` → other; swiftpay — cancel через DELETE, balance; мини-спека `GET /payouts` (список) → other;
два кандидата на create → больший счёт, второй → other + `WARN role_conflict` с hint `endpoints.<id>: create`;
`POST /v2/transfer-orders` (negative word) → < 0.8; `include_paths: ['/v1/payouts*']` отфильтровывает остальное;
пустой результат фильтра → `WARN include_paths_empty`.
**DoD:** `EndpointRoles.new(spec, rules).call.value[:create].operation_id == 'createPayout'`.
**Баллы:** Э1, Ж1 (5), Э4/Ж4 (универсальность ролей).

### [ ] T05 · Analyzers: Auth, Statuses, Errors · Analyzers · волна 2 (∥ T06)
**Читать:** `docs/RULES.md` § 3–4; `docs/SPEC_ANALYSIS_NOVAPAY.md` → Auth, Statuses, Errors; `docs/TEST_SPECS.md` (auth/статусы/ошибки CardPay и SwiftPay).
**Владеет:** `rules/status_map.yml`, `rules/error_actions.yml`, `lib/forge/analyzers/{auth,statuses,errors}.rb`, их spec.
**Сделать:** три анализатора по алгоритмам RULES.md.
**Тесты:** novapay — auth apiKey/`X-API-Key`/`api_key` 0.95; 5 статусов без unmapped; response id `['id']`;
таблица ошибок из SPEC_ANALYSIS (9 строк с учётом ролей 409), `retry_after_header == 'Retry-After'`,
409 create → `treat_as_success` + INFO. cardpay — bearer/`token`; поле `['data','state']`; ON_HOLD unmapped + WARN;
id `['data','transfer_id']` 0.8; код из `errors.0.code`; 503 → retry_backoff. swiftpay — basic (`login`/`password`),
oauth2 альтернатива → UNSUPPORTED `oauth2_alternative`; PENDING_APPROVAL и RETURNED unmapped; problem+json код из `code`.
Мини-спеки: apiKey query → WARN; oauth2 единственный → UNSUPPORTED + bearer; статусы без enum из description
«`paid`, `pending`, `in_transit`» → map 0.6 + WARN `status_from_description`; `approvalPending` → `approval_pending` unmapped.
**DoD:** три анализатора зелёные на трёх спеках и мини-спеках.
**Баллы:** Э1 (7), Ж1 (4+3), Э3/Ж3 (статусы 5).

### [ ] T06 · Analyzers: Webhooks, Amount, Fields, Runner · Analyzers-2 · волна 2 (∥ T05; зависит от T04)
**Читать:** `docs/RULES.md` § 5–8; `docs/SPEC_ANALYSIS_NOVAPAY.md` → Webhooks, Amount, Fields, Предупреждения; `docs/CONTRACT.md` § 3 (реквизиты); `docs/TEST_SPECS.md`.
**Владеет:** `rules/{amount_units,currency_exponents,field_aliases,webhook_signature}.yml`, `lib/forge/analyzers/{webhooks,amount,fields,runner}.rb`, их spec.
**Сделать:** три анализатора и `Runner` (фиксированный порядок, `include_paths`).
**Тесты:** novapay — все значения разделов Webhooks/Amount/Fields SPEC_ANALYSIS, включая `required_if` для
bank_code/card_number и ровно 3 WARN + 3 INFO от всех анализаторов вместе (`Runner.run(spec).values.flat_map(&:warnings)`).
cardpay — webhook из callbacks (INFO), sha512/base64, payload assumed (WARN), `type` как поле события,
transfer.on_hold unmapped; amount major 0.9 (`format('%.2f')`); `merchant_id` → credential INFO; `expiry` unmapped WARN;
`callback_url` → `callback_url`. swiftpay — top-level webhooks (INFO), timestamp → UNSUPPORTED, event_map пустой,
статус из `data.status`, id `data.payment_id`; amount number/multipleOf → major; `beneficiary` oneOf → первый вариант + WARN;
`address` unmapped; `requisite_types == ['bank_account']`. Мини-спеки: integer без маркеров и без minimum → major 0.4 + WARN
`amount_unit_assumed`; JPY → multiplier 1; `amount.value` вложенный; массив → WARN `array_field_unsupported`.
**DoD:** `Runner.run(spec)` возвращает 7 findings; предупреждений на novapay ровно 6 (3 WARN, 3 INFO), на cardpay 5 WARN + 4 INFO, на swiftpay 4 WARN + 3 UNSUPPORTED.
**Баллы:** Э1 (5), Ж1 (3), Э3 (7), Ж3 (4+3+3).

### [ ] T07 · Команда `analyze`, Report · Core · волна 2 (после T05, T06)
**Читать:** `docs/ARCHITECTURE.md` → CLI, Report, Ошибки; `docs/OUTPUT_FORMAT.md` § 6.
**Владеет:** `lib/forge/{cli,report}.rb`, `spec/{cli,report}_spec.rb`, `spec/snapshots/`.
**Сделать:** `Report.text(findings, plan: nil)` и `Report.json`; `cli analyze` со всеми флагами;
сворачивание длинных списков; ошибки без стектрейса; `--debug`.
**Тесты:** snapshot текста `analyze` для трёх спек (`spec/snapshots/<name>_analyze.txt`); `--format json` —
валидный JSON с ключами `spec, endpoints, auth, statuses, errors, webhook, amount, fields, warnings, exit_code`;
каждая битая спека → `error:` + `hint:` в stderr, exit 1, без `.rb:`; `--debug` → стектрейс; `--include-paths`
меняет вывод; первые строки совпадают с ТЗ («Parsing spec...», «Found 5 endpoints: …», «Auth: ApiKeyAuth (header: X-API-Key)», «Webhook signature: X-NovaPay-Signature (HMAC-SHA256»).
**DoD:** **M1 закрыт.** Экран CP1 готов; `README.md` → статус M1.
**Баллы:** Э5 (15), Ж6 (10), Ж4 (1 — сообщения о неподдерживаемом).

---

## M2 — Generate NovaPay

### [ ] T08 · IntegrationPlan, Naming, Validations, Builder · Core · волна 3
**Читать:** `docs/ARCHITECTURE.md` → Plan; `docs/CONTRACT.md` § 1–4; `docs/OUTPUT_FORMAT.md` § 4 (fixtures); `docs/SPEC_ANALYSIS_NOVAPAY.md` → Plan.
**Владеет:** `lib/forge/plan/{integration_plan,builder,naming,validations}.rb`, `spec/plan/`.
**Сделать:** структуры плана; `Naming`; `Validations`; `Builder` (без overrides — заглушка `Overrides.apply` = identity до T09);
fixtures только из examples (синтез — T11); `gateway_config`; `outside_contract`; `GenerationError` при отсутствии create.
**Тесты:** novapay — `class_name 'NovapayService'`, `env_var 'NOVAPAY_BASE_URL'`, `base_url.production`, `amount.minimum_major == 1000`,
4 валидации, `success_statuses == [201, 409]`, `operations[:cancel]` есть, `outside_contract` 2 записи,
`fixtures['callback']['expected_operation_status'] == 'approved'`, `gateway_config == [{external_method: 'sbp_payout', gateway: 'RUB_SBP_WITHDRAW'}, {external_method: 'card_payout', gateway: 'RUB_CARD_WITHDRAW'}]`,
`warnings.size == 6`; `no_create.yaml` → `GenerationError` с hint; `--provider "Nova Pay"` → `NovaPayService`, `NOVA_PAY_BASE_URL`, `nova_pay_service.rb`;
без `--provider` на cardpay → `cardpay` (из «CardPay Transfers API»); swiftpay → `swiftpay`.
**DoD:** план для трёх спек собирается без ошибок; детерминизм: два `build` → `==`.
**Баллы:** Ж2 (5 — контракт), Э3, Ж2 (3 — конфигурация).

### [ ] T09 · Overrides · Analyzers · волна 3 (∥ T10)
**Читать:** `docs/RULES.md` § 9; `examples/overrides/*.yml`.
**Владеет:** `lib/forge/plan/overrides.rb`, `spec/plan/overrides_spec.rb`, `examples/overrides/`.
**Сделать:** схема ключей, валидация с did-you-mean (`DidYouMean::SpellChecker`), применение поле за полем,
`INFO override_applied` на каждое; `paths.include`.
**Тесты:** по одному на каждый ключ схемы (`provider`, `paths`, `base_url`, `endpoints`, `auth`, `statuses`, `events`, `amount`, `fields.*.{source,required,required_if}`, `webhook.*`, `errors`);
неизвестный ключ `statusses` → `SpecError` «did you mean statuses»; `examples/overrides/cardpay.yml` на плане cardpay → 0 WARN, 4 `override_applied`;
overrides не могут создать эндпоинт (`endpoints.nope: create` → `SpecError`).
**DoD:** `--overrides` работает в `analyze`.
**Баллы:** Э4 (3), Ж4 (1).

### [ ] T10 · Renderers::Base, Service, Verifier, заглушка контракта · Renderers · волна 3 (∥ T09)
**Читать:** `docs/OUTPUT_FORMAT.md` § 1 целиком; `docs/CONTRACT.md` целиком; `spec/reference/novapay/novapay_service.rb`; `docs/SPEC_ANALYSIS_NOVAPAY.md` → Reference-тест.
**Владеет:** `lib/provider/*`, `lib/forge/renderers/{base,service}.rb`, `templates/service.rb.erb` + партиалы, `lib/forge/verifier.rb`, `spec/provider/`, `spec/renderers/service_spec.rb`, `spec/reference_spec.rb`, `spec/verifier_spec.rb`.
**Сделать:** заглушку `lib/provider` (код из CONTRACT.md § 5 + `lib/provider.rb`); `Renderers::Base` (поиск шаблона, нормализация);
`Service` + шаблон, покрывающий: api_key/bearer/basic/oauth2-TODO; minor/major (string/number); контейнер реквизитов и варианты
по `required_if`; отсутствие webhook/status/cancel; `outside_contract` хелперы; unmapped → TODO; timestamp-подпись → NotImplementedError.
`Verifier.syntax!(paths)` через `ruby -c`.
**Тесты:** заглушка — по CONTRACT.md § 7; рендер novapay → байт-в-байт равен целевому из OUTPUT_FORMAT § 1 (это первый golden);
`ruby -c` ok; `spec/reference_spec.rb` — все элементы списка SPEC_ANALYSIS → Reference-тест; план «минимум» (без webhook/cancel/status, bearer, major string) →
`ruby -c` ok, `process_callback` возвращает `callbacks_not_supported`, нет `cancel_request`, `Authorization`, `format('%.2f'`;
план basic → `Base64.strict_encode64`; синтаксическая ошибка в шаблоне (тестовый `--templates-dir`) → `VerificationError` с выводом компилятора.
**DoD:** `require 'provider'` + `require 'output/novapay/novapay_service'` без ошибок; `Provider::NovapayService.new(provider: …)` создаётся.
**Баллы:** Э2 (25), Ж2 (5+5+4+4+4), Э3.

### [ ] T11 · IntegrationDoc, Fixtures (+Synthesizer), ServiceSpec · Renderers · волна 3 (после T10)
**Читать:** `docs/OUTPUT_FORMAT.md` § 2–4; `spec/reference/novapay/{INTEGRATION.md,fixtures.json}`.
**Владеет:** `templates/{integration.md,service_spec.rb}.erb`, `lib/forge/renderers/{integration_doc,fixtures,service_spec}.rb`, `lib/forge/fixtures/synthesizer.rb`, `lib/forge/generated_spec_helper.rb`, `spec/renderers/`, `spec/fixtures/synthesizer_spec.rb`, `spec/support/deep_subset.rb`.
**Сделать:** три рендерера; синтезатор; `Verifier.spec!(path)` (rspec на сгенерированном spec).
**Тесты:** `INTEGRATION.md` novapay содержит все заголовки и строки таблиц reference + раздел «Допущения» с 3 строками WARN и 3 INFO;
`fixtures.json` — reference ⊆ наш (`deep_include`); synthesizer: схема без примеров → детерминированный объект (два вызова равны), enum → первый,
pattern `^7\d{10}$` → `'79000000000'`, date-time → `'2026-01-01T00:00:00Z'`; сгенерированный spec novapay зелёный
(`bundle exec rspec output/novapay/novapay_service_spec.rb` через `Verifier`), 11+ примеров; spec для плана без webhook имеет `pending`.
**DoD:** 5 файлов из ТЗ (+ spec) генерируются для novapay; `Verifier.spec!` умеет запускать и парсить итог.
**Баллы:** Ж5 (13), Э5 (5), Ж2 (4 — уведомления, через spec).

### [ ] T12 · Команда `generate`, `bin/integrate`, golden · Core · волна 3 (после T11)
**Читать:** `docs/ARCHITECTURE.md` → CLI, коды выхода; `docs/OUTPUT_FORMAT.md` § 6; `docs/TESTING.md` § 4.
**Владеет:** `lib/forge/cli.rb` (generate), `lib/forge/renderers/{runner,report_file}.rb`, `bin/integrate`, `spec/golden_spec.rb`, `spec/golden/novapay/`, `spec/determinism_spec.rb`, `spec/cli_spec.rb` (generate).
**Сделать:** `generate` со всеми флагами; `--force`, `--strict`, `--no-verify`, `--templates-dir`, `--format json`;
`report.txt`; golden novapay (сгенерировать, **просмотреть глазами**, зафиксировать); `UPDATE_GOLDEN=1`; `rake determinism`.
**Тесты:** golden novapay; `bin/integrate --spec examples/specs/novapay.yaml --provider novapay --lang ruby` → вывод как в README и файлы в `./output/`;
повторный запуск без `--force` → exit 2; `--strict` → exit 4; `--no-verify` пропускает rspec; `--templates-dir` с подменённым шаблоном используется;
`--format json` содержит `outputs`; determinism — sha256 равны.
**DoD:** **M2 закрыт.** README: статус M2, вывод `generate` вставлен.
**Баллы:** Э5 (6+4), Ж6 (4+3+3), Ж7 (3).

---

## M3 — Universal

### [ ] T13 · CardPay: golden, привязки к NovaPay · Analyzers · волна 4 (∥ T18)
**Читать:** `docs/TEST_SPECS.md` § 1–2, § 5; `examples/overrides/cardpay.yml`.
**Владеет:** `rules/`, `lib/forge/analyzers/`, `spec/analyzers/`, `spec/golden/cardpay*/`; шаблоны — только через запрос к человеку (D-xx в NOTES).
**Сделать:** прогнать `generate` на cardpay без и с overrides; каждое падение или неверный вывод — привязка к NovaPay → чинить в анализаторах/словарях.
Реализовать всё из матрицы § 1 для CardPay: bearer, major string, обёртка `data` + suffix-поиск id, `callbacks` как источник, sha512/base64,
поле `state`, `type` как поле события, production-default WARN, отсутствие cancel, `errors.0.code`, credential field.
**Тесты:** golden `cardpay` и `cardpay_overrides`; список WARN/INFO совпадает с TEST_SPECS § 2; сгенерированный spec cardpay зелёный;
golden novapay **не изменился** (или дифф принят человеком).
**DoD:** `generate --spec cardpay.yaml --overrides examples/overrides/cardpay.yml --strict` → exit 0.
**Баллы:** Э4 (7+5), Ж4 (5+3).

### [ ] T14 · SwiftPay (3.1 JSON, payout на счёт) и UNSUPPORTED · Analyzers · волна 4 (после T13)
**Читать:** `docs/TEST_SPECS.md` § 3; `examples/overrides/swiftpay.yml`.
**Владеет:** как T13 + `spec/golden/swiftpay*/`.
**Сделать:** server variables (проверить), basic auth + oauth2 альтернатива → UNSUPPORTED, `allOf`, `oneOf` первый вариант + WARN,
3.1 типы, DELETE как cancel, `problem+json`, top-level `webhooks`, общий тип события + статус из `data.status`, подпись с timestamp →
UNSUPPORTED + `NotImplementedError`, внешний `$ref` в balance → UNSUPPORTED без падения; `external_ref_in_create.yaml` → exit 1.
**Тесты:** golden `swiftpay` и `swiftpay_overrides`; 4 WARN + 3 UNSUPPORTED; exit 0; сгенерированный spec swiftpay зелёный с 1 `pending`;
`no_create.yaml` → `generate` exit 2, `analyze` exit 0 с WARN.
**DoD:** **M3 (спеки) закрыт.** Матрица покрытия TEST_SPECS § 1 — вся зелёная.
**Баллы:** Э4 (3), Ж4 (1+1), Ж1 (3 — доп. условия).

### [ ] T18 · Реальные спеки · QA · волна 4 (∥ T13)
**Читать:** `docs/REAL_SPECS.md` целиком; `docs/TESTING.md` § 9.
**Владеет:** `Rakefile` (namespace `real`), `spec/real_specs_spec.rb`, `examples/real/reports/`, `.gitignore` (real).
**Сделать:** `rake real:fetch` (Net::HTTP, 7 URL из таблицы, пропуск скачанных, таймаут 60 с), `rake real:analyze`
(каждая → `bin/forge analyze` с флагами из таблицы ожиданий → `reports/<name>.txt` + `.json` + сводка `reports/SUMMARY.md`),
`spec/real_specs_spec.rb` (тег `:real`, skip без файлов, снапшоты с `REAL_UPDATE=1`). Каждое падение forge → issue в
`NOTES.md` → «Реальные спеки» с pointer'ом; если фикс тривиален и в `lib/forge/loader.rb`/`ref_resolver.rb` — сделать после согласования.
**Тесты:** 7 `describe`, ожидания из REAL_SPECS § 2 (код выхода, роли, auth); Stripe загружается ≤ 10 с (`Timeout`).
**DoD:** `rake real` зелёный локально; `examples/real/reports/*` закоммичены; README → «Проверено на реальных спецификациях» (черновик таблицы).
**Баллы:** Э4 (15 — доказательство), Ж4 (5), отраслевое «доп. идеи».

---

## M4 — Proof

### [ ] T15 · MockServer, `bin/forge mock`, `bin/e2e` · Renderers · волна 5
**Читать:** `docs/OUTPUT_FORMAT.md` § 5; `docs/CONTRACT.md`; `docs/TESTING.md` § 8.
**Владеет:** `templates/mock_server.rb.erb`, `lib/forge/renderers/mock_server.rb`, `lib/forge/cli.rb` (mock — согласовать с Core), `bin/e2e`, `spec/renderers/mock_server_spec.rb`, `spec/e2e_spec.rb`.
**Сделать:** рендерер мока; команда `mock`; `bin/e2e` (мок на свободном порту, Rack-приёмник webhook, вызов `process_callback(payload, raw_body:, headers:)`,
шаги на экран, exit 0/1). Всё на Ruby.
**Тесты:** мок novapay (Rack::Test): 401 без ключа; 422 на малую сумму; 201 + статус; повтор с тем же `Idempotency-Key` → 409 тот же объект;
`_simulate` шлёт подписанный webhook (WebMock на исходящий, проверка HMAC); мок cardpay: bearer, base64 sha512; e2e novapay и cardpay → `approved`.
**DoD:** `bin/e2e examples/specs/novapay.yaml` печатает `operation approved ✓`; CI job `e2e` зелёный.
**Баллы:** Ж2 (5 «отправка запросов», 4 «уведомления»), отраслевое 6.

### [ ] T19 · Качество: покрытие, негативные, guard · QA · волна 5 (∥ T15)
**Читать:** `docs/TESTING.md` § 3, § 5, § 10; `docs/PROCESS.md` § 5.
**Владеет:** `spec/` (добавление тестов в любые файлы), `.rubocop.yml` (только ужесточение), `Rakefile` (`guard:*`, `licenses`, `generated:*`).
**Сделать:** довести SimpleCov до порогов (line ≥ 90, branch ≥ 75, файл ≥ 70) осмысленными тестами по таблице TESTING § 3;
негативные тесты CLI полностью; `rake licenses`; `rake generated:spec` (rspec на всех output); `rake guard:vendor` в `ci`;
`rake readme:check`. Найденные баги → минимальные фиксы с тестом (сообщить человеку).
**Тесты:** сами тесты; `rake ci` зелёный.
**DoD:** `coverage/.last_run.json` ≥ порогов; rubocop 0; `rake ci` < 3 мин.
**Баллы:** Э6 (10), Ж7 (4+3).

---

## M5 — Ship

### [ ] T16 · README, Docker, CI финал · Docs · волна 5–6
**Читать:** `docs/PROCESS.md` § 7; `docs/CRITERIA.md`; `docs/REAL_SPECS.md` § 4; README-скелет из комплекта.
**Владеет:** `README.md`, `Dockerfile`, `.github/workflows/ci.yml` (совместно с QA), `docs/` (вычитка), `examples/real/reports/SUMMARY.md`.
**Сделать:** README без «(план)»: быстрый старт (Docker и без), пайплайн-схема, реальный вывод `analyze`/`generate`, overrides how-to,
универсальность (3 спеки + таблица реальных), «Критерий → где смотреть», «Почему без нейросети», ограничения, что дальше;
`docker run` проверен с нуля; CI: все job'ы (`lint`, `test`, `generate`, `generated-specs`, `e2e`, `docker`, `real-specs` manual).
**Тесты:** `rake readme:check` выполняет команды быстрого старта; CI зелёный на `main`.
**DoD:** свежий `git clone` + `docker build` + одна команда из README дают результат за ≤ 2 мин.
**Баллы:** Ж6 (4), Ж7 (3), Э5 (5), отраслевое «полнота» 8.

### [ ] T20 · Демо и питч · Lead + Docs · волна 6
**Владеет:** `bin/demo` (Ruby: последовательность команд с паузами и заголовками), `docs/PITCH.md`, `docs/DEMO_CP3.md`.
**Сделать:** `bin/demo` (generate → rspec → e2e → покажи файлы), 7 слайдов текстом, скрипт на 7 минут, слайд «критерий → где в репозитории»,
явный список killer-фич под «дополнительные идеи»: генерируемый RSpec, мок-сервер + e2e, отчёт с confidence и допущениями,
overrides как рекомендованный механизм, 7 реальных API, детерминизм без LLM.
**DoD:** три прогона `bin/demo` ≤ 4 мин каждый; скринкаст-бэкап записан.

### [ ] T21 · Ревью-проход · Reviewer · волна 6
**Сделать:** `/review` на `main` целиком (по чек-листу PROCESS § 4), результат в `NOTES.md` → «Ревью». Блокеры → T17.

### [ ] T17 · Полировка по замечаниям CP3 · Core · после CP3
Только багфиксы и текст по `NOTES.md` → «CP3». Новые фичи — нет. Freeze вс 22:00 ALA.

---

## Резерв (только если всё выше закрыто и до вс 18:00 ALA)

- R1 · `json_schemer`: валидация фикстур по схемам спеки, отчёт о расхождениях примеров со схемой.
- R2 · `fields.<path>.variant` для выбора варианта `oneOf` через overrides (закрывает последний WARN SwiftPay).
- R3 · Статус-запрос через POST с id в теле (`status_request_field`) — закрывает Plaid.
- R4 · Экспорт `.http`/Postman-коллекции из фикстур.
- R5 · Swagger 2.0 → 3.0 конвертация (без гема).

## Остаток

(агенты дописывают сюда незавершённые части карточек: `T05: не сделан status_from_description, тест pending`)
