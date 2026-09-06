# forge — генератор интеграций с платёжными провайдерами из OpenAPI

> Хакатон Space Payments, задача 1. Вход — OpenAPI 3.0/3.1 спецификация провайдера выплат
> (YAML или JSON). Выход — готовый Ruby-сервис по контракту `Provider::BaseService`, гайд
> интеграции, тестовые фикстуры, RSpec-тесты сервиса, мок-сервер провайдера и отчёт о том,
> что и с какой уверенностью распознано. Без нейросетей: правила, словари, детерминизм.

Зачем читать: это вход для жюри и экспертов. Пять минут — и вы знаете, как запустить,
что получается, где в коде каждый критерий и что мы сознательно не делаем.

> Статус: все этапы M1–M4 закрыты (`docs/PLAN.md`); `rake ci` зелёный за ~15 с; `bin/e2e` доводит
> выплату до `approved` на сгенерированном моке для NovaPay, CardPay, SwiftPay, Райффайзена и OAuth2-провайдера; 25 реальных API анализируются без падений.

> Статус: **M4 Proof закрыт** — `bin/e2e examples/specs/novapay.yaml` поднимает сгенерированный мок, создаёт выплату, получает подписанный webhook и печатает `operation approved ✓`; то же для CardPay, SwiftPay (подпись `t=…,v1=…`), Райффайзена и OAuth2-провайдера (`spec/fixtures/oauth2_payout.yaml`). Реальные спеки (25 API) — отчёты в `examples/real/reports/`; PayPal, Velo, Dwolla и Open Banking получают токен OAuth2 client_credentials.
>
> Ранее: **M3 (спеки) закрыт** — golden для NovaPay, CardPay и SwiftPay (с overrides и без), `generate --overrides … --strict` для CardPay даёт exit 0. Далее — реальные спеки (T18), мок и e2e (T15).
>
> Ранее: **M2 Generate закрыт** — `bin/forge generate` для NovaPay даёт сервис, spec (14 примеров, зелёный), `INTEGRATION.md`, `fixtures.json`, `report.txt`; golden и determinism зелёные. Дальше — M3 Universal (CardPay/SwiftPay golden, реальные спеки).

## Быстрый старт

Без Docker (Ruby ≥ 3.3):

```bash
bundle install
bin/forge analyze  --spec examples/specs/novapay.yaml
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/out/novapay --force
bundle exec rspec -I lib -I tmp/out/novapay tmp/out/novapay/novapay_service_spec.rb
```

Команда из условия задачи (обёртка над `generate`, вывод в `./output/`):

```bash
bin/integrate --spec provider_api.yaml --provider novapay --lang ruby
```

Docker:

```bash
docker build -t forge .
docker run --rm -v "$PWD/examples:/app/examples" -v "$PWD/output:/app/output" forge \
  generate --spec examples/specs/novapay.yaml --out output/novapay --force
```

Полная проверка (то же, что CI): `bundle exec rake ci`. Быстрая: `bundle exec rake check`.


<details><summary>Вывод <code>bin/forge generate --spec examples/specs/novapay.yaml --out output/novapay</code></summary>

```
Parsing spec... ok (openapi 3.0.3, NovaPay Payout API 1.0.0)
Found 5 endpoints: POST /payouts, GET /payouts/{payout_id}, POST /payouts/{payout_id}/cancel,
                   POST /webhooks/payout, GET /balance
  create   POST /payouts                              createPayout             confidence 0.95
  status   GET /payouts/{payout_id}                   getPayoutStatus          confidence 0.90
  cancel   POST /payouts/{payout_id}/cancel           cancelPayout             confidence 0.95   (outside contract → cancel_request)
  webhook  POST /webhooks/payout                      payoutWebhook            confidence 0.90
  balance  GET /balance                               getBalance               confidence 0.85   (outside contract → fetch_balance)
Auth: ApiKeyAuth (api_key, header: X-API-Key) → credentials.api_key
Statuses (status): pending, processing → in_progress; completed → approved; failed, cancelled → rejected
Errors: 400 validation_error → reject; 401 (create) unauthorized → alert_block;
        401 (status) unauthorized → alert_block; 402 insufficient_balance → retry;
        404 not_found → reject; 409 (create) duplicate → treat_as_success;
        409 (cancel) invalid_status → reject; 422 validation_error → reject;
        429 rate_limit_exceeded → retry_backoff (Retry-After); 500 internal_error → retry
Webhook signature: X-NovaPay-Signature (HMAC-SHA256, raw body, hex) → credentials.callback_secret
Webhook events: payout.completed → approved; payout.failed → rejected; payout.processing → in_progress; payout.cancelled → rejected
Amount: integer, minor units (×100), min 1000 RUB — source: amount (integer, min 100000) → minor units: 'Сумма в копейках'
Fields: 8 request fields, 0 unmapped (recipient: sbp, card)
Generating service...
Generating integration guide...
Generating test fixtures...
Generating service spec...
Generating extras...
Generating mock server...
Verifying generated code... ok (ruby -c ×4, rspec skipped: --no-verify)
Output:
  ./novapay_service.rb
  ./INTEGRATION.md
  ./fixtures.json
  ./novapay_service_spec.rb
  ./novapay_extras.rb
  ./mock_server.rb
  ./report.txt
Warnings (3):
  WARN         signature_encoding_assumed X-NovaPay-Signature: encoding not stated; hex assumed
        hint: webhook.signature_encoding: hex|base64  (overrides.yml)
  WARN         conditional_required       recipient.bank_code: required only for type=sbp (from description)
        hint: fields.recipient.bank_code.required_if: { field: type, equals: sbp }  applied; verify
  WARN         conditional_required       recipient.card_number: required only for type=card (from description)
        hint: fields.recipient.card_number.required_if: { field: type, equals: card }  applied; verify
Info (3):
  INFO         outside_contract           POST /payouts/{payout_id}/cancel (cancelPayout) — generated as `cancel_request` helper
  INFO         outside_contract           GET /balance (getBalance) — generated as `fetch_balance` helper
  INFO         duplicate_as_success       HTTP 409 returns the success schema (PayoutResponse); treated as success
        hint: the service reads the payout from the body
Done: 7 files, 3 warnings, 0 unsupported. Exit 0.
```

</details>

## Что получается

```
output/novapay/
├── novapay_service.rb        # Provider::NovapayService < BaseService: ровно четыре метода контракта
├── novapay_extras.rb         # Provider::NovapayExtras < NovapayService: cancel_request, fetch_balance (вне контракта)
├── novapay_service_spec.rb   # RSpec на WebMock и fixtures.json — доказательство, что сервис работает
├── INTEGRATION.md            # авторизация, методы, маппинг статусов, ошибки, подпись webhook, ДОПУЩЕНИЯ
├── fixtures.json             # примеры запросов/ответов/уведомлений и ожидаемые статусы операции
├── mock_server.rb            # Sinatra-мок провайдера из той же спеки (demo и e2e)
└── report.txt                # что распознано, confidence, WARN / UNSUPPORTED с подсказками
```

Реальный вывод `bin/forge analyze --spec examples/specs/novapay.yaml` (первые строки — дословно как в ТЗ; снапшот `spec/snapshots/novapay_analyze.txt`):

```
Parsing spec... ok (openapi 3.0.3, NovaPay Payout API 1.0.0)
Found 5 endpoints: POST /payouts, GET /payouts/{payout_id}, POST /payouts/{payout_id}/cancel,
                   POST /webhooks/payout, GET /balance
  create   POST /payouts                              createPayout             confidence 0.95
  status   GET /payouts/{payout_id}                   getPayoutStatus          confidence 0.90
  cancel   POST /payouts/{payout_id}/cancel           cancelPayout             confidence 0.95   (outside contract → cancel_request)
  webhook  POST /webhooks/payout                      payoutWebhook            confidence 0.90
  balance  GET /balance                               getBalance               confidence 0.85   (outside contract → fetch_balance)
Auth: ApiKeyAuth (api_key, header: X-API-Key) → credentials.api_key
Statuses (status): pending, processing → in_progress; completed → approved; failed, cancelled → rejected
Errors: 400 validation_error → reject; 401 (create) unauthorized → alert_block;
        401 (status) unauthorized → alert_block; 402 insufficient_balance → retry;
        404 not_found → reject; 409 (create) duplicate → treat_as_success;
        409 (cancel) invalid_status → reject; 422 validation_error → reject;
        429 rate_limit_exceeded → retry_backoff (Retry-After); 500 internal_error → retry
Webhook signature: X-NovaPay-Signature (HMAC-SHA256, raw body, hex) → credentials.callback_secret
Webhook events: payout.completed → approved; payout.failed → rejected; payout.processing → in_progress; payout.cancelled → rejected
Amount: integer, minor units (×100), min 1000 RUB — source: amount (integer, min 100000) → minor units: 'Сумма в копейках'
Fields: 8 request fields, 0 unmapped (recipient: sbp, card)
Warnings (3):
  WARN         signature_encoding_assumed X-NovaPay-Signature: encoding not stated; hex assumed
        hint: webhook.signature_encoding: hex|base64  (overrides.yml)
  WARN         conditional_required       recipient.bank_code: required only for type=sbp (from description)
        hint: fields.recipient.bank_code.required_if: { field: type, equals: sbp }  applied; verify
  WARN         conditional_required       recipient.card_number: required only for type=card (from description)
        hint: fields.recipient.card_number.required_if: { field: type, equals: card }  applied; verify
Info (3):
  INFO         outside_contract           POST /payouts/{payout_id}/cancel (cancelPayout) — generated as `cancel_request` helper
  INFO         outside_contract           GET /balance (getBalance) — generated as `fetch_balance` helper
  INFO         duplicate_as_success       HTTP 409 returns the success schema (PayoutResponse); treated as success
        hint: the service reads the payout from the body
Done: 3 warnings, 0 unsupported. Exit 0.
```

Формат — `docs/OUTPUT_FORMAT.md` § 6.

## Веб-интерфейс (демо)

CLI — основной интерфейс (по условиям задачи). Веб-слой — тонкая обёртка над теми же классами для демо
жюри: загрузить спеку и overrides, увидеть отчёт, открыть/скачать 7 файлов, запустить сгенерированный
RSpec и e2e (мок + webhook) кнопкой. Без базы и без новых гемов (Sinatra + Puma уже в Gemfile).

```bash
bin/forge-web                                  # http://localhost:8080 (PORT, FORGE_WORKDIR)
docker compose up --build                      # то же в контейнере, данные прогонов — в volume forge-data
docker build --target web -t forge-web . && docker run --rm -p 8080:8080 forge-web
```

Деплой на сервер: любой хост с Docker — `docker compose up -d`; за reverse-proxy (nginx/Caddy) на 8080.
Прогоны хранятся на диске (`FORGE_WORKDIR`), секретов в них нет: `credentials` в сгенерированном коде —
плейсхолдеры. Ограничение размера спеки — 20 МБ. Обработчик `Forge::Error` показывает ошибку с pointer и hint.

## Как это работает

```
                 rules/*.yml                overrides.yml
                     │                           │
provider_api.yaml ─▶ Load ─▶ IR ─▶ Analyze ─▶ Plan ─▶ Render ─▶ Verify ─▶ Report
                      │             │           │        │         │
                  SpecError     Findings  IntegrationPlan  files  ruby -c / rspec
```

| Стадия | Что делает | Где |
|---|---|---|
| Load | YAML/JSON → hash, проверка `openapi: 3.x`, резолв локальных `$ref`, ошибки с JSON-pointer и подсказкой | `lib/forge/loader.rb`, `ref_resolver.rb` |
| IR | неизменяемые `Data.define`: Spec, Endpoint, Schema… — ничего не знает о платежах | `lib/forge/ir/` |
| Analyze | 7 анализаторов (роли эндпоинтов, auth, статусы, ошибки, webhook, единицы суммы, поля) → `Finding(value, confidence, source, warnings)` | `lib/forge/analyzers/`, словари `rules/*.yml` |
| Plan | findings → `IntegrationPlan`; наложение `overrides.yml`; валидации из схемы; фикстуры | `lib/forge/plan/` |
| Render | ERB-шаблоны получают только план, никогда сырой OpenAPI | `lib/forge/renderers/`, `templates/*.erb` |
| Verify | `ruby -c` + запуск сгенерированного spec | `lib/forge/verifier.rb` |
| Report | текст как в ТЗ + WARN / UNSUPPORTED / INFO с подсказками; `--format json` | `lib/forge/report.rb` |

Ключевые принципы:

- **Знание о провайдере не живёт в коде.** Всё специфичное — в `rules/*.yml` (синонимы статусов,
  веса сигналов ролей, алиасы полей, маркеры единиц суммы) или в пользовательском `overrides.yml`.
  `rake guard:vendor` падает, если в `lib/` встречается имя провайдера.
- **Неоднозначное не угадываем молча.** Из структуры спеки — автоматически. То, что лежит текстом в
  `description` (единицы суммы, условная обязательность, кодировка подписи), — WARN в отчёте,
  `# TODO(forge)` в коде, раздел «Допущения» в `INTEGRATION.md` и ключ в `overrides.yml`.
  Подход подтверждён организаторами письменно (`docs/QA_SESSION_1.md` § 7).
- **Детерминизм.** Одинаковый вход → байт-в-байт одинаковый выход (`rake determinism`). Никаких
  сетевых вызовов и LLM во время генерации.
- **Строгий режим не прерывает работу.** `--strict` генерирует все файлы и печатает полный отчёт, а
  ненулевой код (4) возвращает только в конце, если остались WARN/UNSUPPORTED — удобно для CI, где
  «допущение без overrides» должно быть красным, но артефакты всё равно нужны.
- **Падаем только когда генерировать нечего** (нет create-эндпоинта → exit 2 с подсказкой, как указать
  его в overrides). Всё остальное — WARN/UNSUPPORTED, а не молчание и не крэш.
- **Любой файл пользователя — не крэш.** Битая структура (`responses: nope`, `parameters: {…}`, `$ref: 5`,
  YAML-теги `!ruby/…`, вложенность в тысячи уровней) → `SpecError` с pointer (exit 1). Всё, чего
  конвейер не ожидал, → `internal error: …` с подсказкой (exit 2, стектрейс только с `--debug`);
  веб показывает то же сообщение вместо «Internal Server Error». Проверено фаззингом: 170 враждебных
  спек, overrides и параметров формы.

## Как переопределить решение (overrides)

```yaml
# overrides.yml — общий механизм, не привязка к провайдеру
amount:
  unit: minor                            # minor (копейки) | major (рубли); multiplier, minimum_major
statuses:
  ON_HOLD: in_progress                   # статус провайдера → статус Space Payments
fields:
  recipient.bank_code:
    required_if: { field: type, equals: sbp }
  destination.card.expiry:                 # поле без источника → своё выражение на стороне operation
    source: "format('%02d/%02d', operation.payout_requisite.dig('card', 'expiry_month'), operation.payout_requisite.dig('card', 'expiry_year') % 100)"
webhook:
  signature_encoding: hex                # hex | base64
  signature_payload: raw_body            # raw_body | fields
endpoints:
  createTransfer: create                 # роль эндпоинта, если эвристика ошиблась
paths:
  include: ['/v1/payouts*']              # ограничить анализ большой спеки
```

`bin/forge generate --spec … --overrides overrides.yml`. Каждое применённое переопределение
попадает в отчёт как `INFO override_applied`. Полная схема — `docs/RULES.md` § 9, примеры с
комментариями — `examples/overrides/`.

## Универсальность: четыре спеки и двадцать реальных API

| Спека | Что отличается от NovaPay | Результат без overrides | С overrides |
|---|---|---|---|
| `examples/specs/novapay.yaml` (ТЗ) | эталон | 3 WARN, 4 INFO (один — расхождение примера 401 с enum в самом ТЗ), exit 0 | не нужны |
| `examples/specs/cardpay.yaml` | bearer, сумма строкой в рублях, статусы `NEW/SUCCESS/DECLINED/ON_HOLD` в поле `state`, обёртка `data`, webhook через `callbacks`, HMAC-SHA512 base64, нет отмены | 5 WARN, 4 INFO | 0 WARN |
| `examples/specs/swiftpay.json` | OpenAPI 3.1 JSON, basic auth + oauth2, `oneOf` получателя, внешний `$ref`, подпись `t=…,v1=…` с timestamp, `problem+json`, top-level `webhooks` | 5 WARN, 2 UNSUPPORTED, exit 0; e2e → approved | 0 WARN (2 UNSUPPORTED) |
| `examples/specs/raiffeisen.yaml` (реальная спека Райффайзенбанка, СБП) | OpenAPI 3.0 на русском, bearer в тексте, контейнер `payoutParams`, тип `payoutMethod: SBP`, статус в объекте `status.value`, `x-webhooks` + `x-examples`, подпись описана текстом | 4 WARN, exit 0; e2e → approved | 1 WARN |

Все три покрыты golden-тестами байт-в-байт (`spec/golden/`, с overrides и без).

Реальные спецификации (Stripe, Adyen Payout и Transfers, PayPal Payouts, Paystack, Square, Plaid):
`bundle exec rake real` скачивает их и прогоняет `analyze`; отчёты — `examples/real/reports/`.
Ожидания и найденные ограничения — `docs/REAL_SPECS.md`. **WARN на чужой спеке — это честность
инструмента, а не сбой.**

## Проверено на реальных спецификациях

`rake real` скачивает двадцать открытых спек (7 первой волны в таблице ниже и 13 второй) (`examples/real/`, в git не попадают), прогоняет `analyze` и
сравнивает отчёты со снапшотами `examples/real/reports/*.txt`. Ни одна не роняет инструмент; WARN — это
честность, а не сбой: каждый закрывается строкой в `overrides.yml`.

| Провайдер | Что распознано автоматически | Что требует overrides / ручного кода | Отчёт |
|---|---|---|---|
| Adyen Payout v68 | create `POST /payout`, basic auth (apiKey — альтернатива), сумма `amount.value` в minor units | нет status-эндпоинта и webhook (WARN); поля с большой вложенностью | [adyen_payout.txt](examples/real/reports/adyen_payout.txt) |
| Adyen Transfers v4 | create/status, apiKey в query (WARN), 20+ статусов из enum по словарю | 100+ редких статусов → `statuses.<X>` (отчёт сворачивает список) | [adyen_transfers.txt](examples/real/reports/adyen_transfers.txt) |
| PayPal Payouts | create/status/cancel, OAuth2 client_credentials: токен по `POST /v1/oauth2/token`, затем Bearer | batch `items[]` — массивы не мапятся (WARN) | [paypal_payouts.txt](examples/real/reports/paypal_payouts.txt) |
| Paystack | `--include-paths /transfer*`: create `transfer_initiate`, status, balance; `$ref` на path-pointer с `~1` и `%7B` | конфликт status/verify и DELETE recipient как cancel → `endpoints.*` | [paystack.txt](examples/real/reports/paystack.txt) |
| Stripe (8 МБ) | `--include-paths /v1/payouts*`: create/status/cancel, статусы из description, сумма в cents, form-urlencoded тело (WARN); загрузка 0.1 с | webhook в спеке нет | [stripe.txt](examples/real/reports/stripe.txt) |
| Square | статус-эндпоинт; create нет → WARN `no_create_endpoint` (`generate` → exit 2 с подсказкой); битые `$ref` вне контракта → UNSUPPORTED | — | [square.txt](examples/real/reports/square.txt) |
| Plaid | `--include-paths /transfer/*`: create `/transfer/create`, status `POST /transfer/get` (id в теле), cancel; apiKey в заголовках | 40+ полей запроса без источника → overrides | [plaid.txt](examples/real/reports/plaid.txt) |

Сводка: [SUMMARY.md](examples/real/reports/SUMMARY.md).

Вторая волна (13 спек, `rake real` скачивает и их): Velo, Increase, Mollie, Dwolla, Wise, Open Banking UK — выплаты,
сервисы генерируются, сгенерированные RSpec зелёные; NOWPayments, Klarna, PAYONE Link — честный `no_create_endpoint`
(exit 2); VTEX, Adyen Balance Platform и Adyen Checkout — pay-in/конфигурация, create только с WARN `low_confidence`;
GOV.UK Pay — Swagger 2.0, понятная ошибка. Таблица и ссылки — `docs/REAL_SPECS.md` § 1a. Этот прогон вскрыл и закрыл
9 дефектов генератора на «диких» спеках (ключи с точкой, пустое тело 201, минимум в один цент, `Currency` как имя
переменной, общий `$ref`-пример у create и status и др. — `NOTES.md` D-27).

Живые API: сервисы, сгенерированные из этих спек, проходят собственные RSpec (6 из 7 спек с create; Square —
честный exit 2) и отправляли запросы в настоящие sandbox Stripe, Paystack, PayPal и Adyen с неверным ключом:
реальные 401 → `provider.invalid_credentials`, 400 с неизвестным кодом → `provider.unknown_error`, сетевой
сбой → `provider.unavailable`. Этот прогон вскрыл и закрыл 10 дефектов генерации (`docs/AUDIT.md` § 5a).

## Критерий → где смотреть

| Критерий (жюри/эксперты) | Где в репозитории |
|---|---|
| Разбор спецификации: методы, параметры, auth, статусы, ошибки, webhook | `lib/forge/analyzers/*.rb`, `rules/*.yml`, `bin/forge analyze`, `spec/analyzers/`, `spec/snapshots/` |
| Сервис по контракту `Provider::BaseService`, запросы, статус, ошибки, уведомления, конфигурация | `templates/service.rb.erb`, `lib/provider/base_service.rb` (контракт — `docs/CONTRACT.md`), `output/<p>/<p>_service.rb`, `BASE_URL`/`credentials` |
| Преобразование данных: статусы, поля, единицы, обязательность | `rules/status_map.yml`, `rules/field_aliases.yml`, `rules/amount_units.yml`, `lib/forge/analyzers/fields.rb`, `.compact` и `required_if` в шаблоне |
| Универсальность | три спеки + golden, `examples/overrides/`, `--templates-dir`, `rake guard:vendor`, секция UNSUPPORTED |
| Документация и тестовые материалы | `output/<p>/INTEGRATION.md` (с «Допущениями»), `fixtures.json`, генерируемый `*_service_spec.rb` |
| Удобство и демонстрация | этот README, `bin/integrate`, коды выхода 0–4, ошибки с pointer + hint, `bin/e2e`, `bin/demo` |
| Качество реализации | шесть стадий по каталогам, `rubocop` 0, покрытие ≥ 90 %, обработка ошибок разбора/генерации (`spec/fixtures/broken/`, `spec/cli_spec.rb`), CI |
| Дополнительные идеи | генерируемый RSpec как доказательство; мок-сервер из той же спеки + e2e `create → webhook → approved`; отчёт с confidence; overrides как рекомендованный механизм; прогон на реальных API; детерминизм |

Подробная разбалловка — `docs/CRITERIA.md`.

## Ограничения (честно)

- Только OpenAPI 3.0/3.1 (Swagger 2.0 → понятная ошибка exit 1). Только выплаты (payout); pay-in —
  «что дальше».
- Внешние `$ref` (`other.yaml#/…`, `http…`) и циклы: в схеме запроса create — ошибка exit 1, иначе
  UNSUPPORTED + заглушка `{}`.
- OAuth2: генерируется только `client_credentials` (`tokenUrl` из спеки, `client_id`/`client_secret` в
  credentials, токен кэшируется без учёта `expires_in`); другие flows → bearer с `TODO`. Подпись `t=…,v1=…` (Stripe-стиль) проверяется как HMAC над
  `"<t>.<raw body>"` (WARN: схема взята из описания); прочие timestamp/nonce-схемы → `NotImplementedError`
  в `verify_signature!` с пояснением.
- `oneOf` получателя: по умолчанию первый вариант + WARN; выбор — `fields.<path>.variant: <SchemaName>`.
- Form-urlencoded тела (Stripe): отправляются как `form:` с плоскими ключами `parent[child]` + WARN
  `media_type_form`; Stripe-стиль вложенности совпадает, другие кодировки — проверить с провайдером.
- Статус через `POST` с id в теле (Plaid `/transfer/get`) поддержан; статус через query-параметр — только
  если параметр назван id/code/reference.
- Массивы полей (PayPal `items[]`) не мапятся автоматически (WARN + `[]`).
- Идентификаторы подключения в пути (`/client/{clientHashId}/wallet/{walletHashId}/…`, Nium-стиль): в URL из
  operation подставляется только id выплаты, остальные `{param}` берутся из `credentials.<param>`
  (WARN `path_params_from_credentials`, ключи перечислены в INTEGRATION.md «Заполнить вручную»).
- Примеры из спеки сверяются с её схемами (`INFO fixture_schema_mismatch`), но берутся как есть.
- Секреты (API-ключ, HMAC secret) в документации нет — генерируются как `credentials.*` с пометкой
  для ручного заполнения.

## Почему без нейросети

По условию инструмент не может вызывать LLM. Это оказалось преимуществом: каждое решение
генератора объяснимо (`source: "operationId 'createPayout' matches /payout/; POST without path param"`),
воспроизводимо и проверяемо тестами. Словари в `rules/` расширяются без изменения кода — это и есть
«предусмотрено добавление новых правил».

## Разработка

- Контекст для агентов и людей — `CLAUDE.md`; процесс — `docs/PROCESS.md`; бэклог — `docs/AGENT_TASKS.md`.
- Ruby 3.3: `.mise.toml` в корне, `mise install && bundle install`.
- `bundle exec rake check` — lint + тесты + guard. `bundle exec rake ci` — всё, что делает CI.
- Golden обновляются осознанно: `UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb`, затем diff.
- `bundle exec rake fuzz` — фаззинг: враждебные спеки/overrides/параметры формы против веб-приложения,
  случайные структурные мутации спек через конвейер (`SEED=… ROUNDS=…`), враждебные запросы к мокам.
  Красный = исключение вне `Forge::Error` или ответ 5xx. Корпус — `spec/fuzz/corpus/*.yml`.
- Решения и обратная связь экспертов — `NOTES.md`.

## Что дальше

Pay-in (депозиты) тем же пайплайном; Swagger 2.0 через конвертацию; batch-выплаты (массивы полей);
полная JSON-Schema-валидация фикстур (`json_schemer`, сейчас — встроенная проверка типов/required/enum);
интеграция с CI Space Payments как шаг «новый провайдер → PR с сервисом и тестами».

## Лицензия

MIT. Все зависимости — MIT/Apache/BSD (`bundle exec rake licenses`).
