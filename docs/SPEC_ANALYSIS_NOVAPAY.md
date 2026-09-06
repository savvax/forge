# Эталонный разбор `examples/specs/novapay.yaml`

Зачем читать: это ответы, которые должны выдать анализаторы и план на эталонной спеке. Тесты
карточек T03–T08 и T10–T12 проверяют именно эти значения. Если анализатор даёт другое — сначала
ищем ошибку в анализаторе/словаре, и только потом осознанно меняем этот документ.

## Load / IR (T02, T03)

| Что | Значение |
|---|---|
| `openapi` | `3.0.3` |
| `info.title` / `version` | `NovaPay Payout API` / `1.0.0` |
| `servers` | `https://api.sandbox.novapay.example/v1` (Sandbox), `https://api.novapay.example/v1` (Production) |
| `$ref` после резолва | ни одного ключа `$ref`; `x-forge-ref-name` есть у `CreatePayoutRequest`, `Recipient`, `PayoutResponse`, `PayoutError`, `WebhookPayload`, `ErrorResponse` |
| Эндпоинтов | **5**: `POST /payouts`, `GET /payouts/{payout_id}`, `POST /payouts/{payout_id}/cancel`, `POST /webhooks/payout`, `GET /balance` |
| `POST /payouts` параметры | `Idempotency-Key` (header, optional, `format: uuid`) — из `$ref` `#/components/parameters/IdempotencyKey` |
| `POST /payouts` ответы | **8**: 201, 400, 401, 402, 409, 422, 429, 500 |
| `POST /payouts` security | `[{'ApiKeyAuth' => []}]` |
| `POST /webhooks/payout` security | `[]` (явно пусто) |
| `Recipient.phone.pattern` | `^7\d{10}$` |
| `CreatePayoutRequest.amount.minimum` | `100000` |
| `CreatePayoutRequest.required` | `[amount, currency, external_id, recipient]` |
| `Recipient.required` | `[type, phone]` |
| Примеры | request `sbp_payout`; response 201 example; webhook examples `completed`, `failed` |
| `RateLimited.headers` | `Retry-After` (integer) |

## EndpointRoles (T04)

| Роль | Эндпоинт | operationId | Confidence | Сигналы |
|---|---|---|---|---|
| create | `POST /payouts` | `createPayout` | **0.95** | method_post 0.30 + payout_word(payouts) 0.25 + create_word(createPayout) 0.20 + no_path_param 0.10 + has_request_body 0.10 |
| status | `GET /payouts/{payout_id}` | `getPayoutStatus` | **0.90** | method_get 0.30 + payout_word 0.25 + has_path_param 0.20 + status_word(status/get) 0.15 |
| cancel | `POST /payouts/{payout_id}/cancel` | `cancelPayout` | **0.95** | method_post 0.25 + payout_word 0.20 + cancel_word_in_path 0.30 + cancel_word_in_operation 0.10 + has_path_param 0.10 |
| webhook | `POST /webhooks/payout` | `payoutWebhook` | **0.90** | webhook_word_in_path 0.40 + security_explicitly_empty 0.20 + signature_header_param(X-NovaPay-Signature) 0.20 + method_post 0.10 |
| balance | `GET /balance` | `getBalance` | **0.85** | balance_word_in_path 0.50 + method_get 0.25 + no_path_param 0.10 |
| other | — | — | — | пусто |

Все ≥ 0.8 → без WARN.

## Auth (T05)

`{type: 'api_key', scheme_name: 'ApiKeyAuth', header: 'X-API-Key', prefix: nil, credential_key: 'api_key', location: 'header'}`, confidence 0.95.
`auth_headers` в коде: `{ 'X-API-Key' => credentials.fetch('api_key') }`.

## Statuses (T05)

Поле: `PayoutResponse.status` (enum) → `field_path: ['status']`, confidence 0.95.

| Provider | Space Payments |
|---|---|
| pending | in_progress |
| processing | in_progress |
| completed | approved |
| failed | rejected |
| cancelled | rejected |

`unmapped: []`. Response id: `['id']` (0.95). Response status: `['status']`.

## Errors (T05) — 8 строк

| HTTP | Роль | Код провайдера (источник) | internal_code | action |
|---|---|---|---|---|
| 400 | create | — (без примера; enum PayoutError первый = validation_error) | validation_error | reject |
| 401 | create, status | unauthorized (example Unauthorized) | invalid_credentials | alert_block |
| 402 | create | insufficient_balance (example) | insufficient_balance | retry |
| 404 | status | not_found (example) | not_found | reject |
| 409 | create | схема = PayoutResponse (успех) | duplicate | **treat_as_success** (+ `INFO duplicate_as_success`) |
| 409 | cancel | invalid_status (example) | invalid_status | reject |
| 422 | create | validation_error (example) | validation_error | reject |
| 429 | create | rate_limit_exceeded (example) | rate_limit | retry_backoff |
| 500 | create | — | internal_error | retry |

(409 — две строки по ролям; в `ERROR_MAP` сервиса 409 отсутствует, т. к. для create это успех; для
`cancel_request` — отдельная ветка `invalid_status`.) `retry_after_header: 'Retry-After'`.
`codes` для документации: validation_error, insufficient_balance, recipient_not_found, bank_unavailable,
amount_limit_exceeded, rate_limit_exceeded, internal_error (enum `PayoutError.code`).

`ERROR_MAP` в сервисе (как в ТЗ + 404):
`{400 => 'validation_error', 401 => 'invalid_credentials', 402 => 'insufficient_balance', 404 => 'not_found', 422 => 'validation_error', 429 => 'rate_limit', 500 => 'internal_error'}`.

## Webhooks (T06)

| Что | Значение | Confidence / источник |
|---|---|---|
| endpoint | `POST /webhooks/payout` | роль из paths |
| signature.header | `X-NovaPay-Signature` | header-параметр с `signature` (0.40) |
| signature.algorithm | `sha256` | description «HMAC-SHA256» (0.30) |
| signature.payload | `raw_body` | description «подпись тела запроса» → маркер `тела` (0.15) |
| signature.encoding | `hex` | **не указано → default** → `WARN signature_encoding_assumed` |
| signature.secret_key | `callback_secret` | словарь |
| confidence | 0.85 | 0.40 + 0.30 + 0.15 (encoding не найден) |
| event_field | `event` | enum есть |
| event_map | `payout.completed → approved`, `payout.failed → rejected`, `payout.processing → in_progress`, `payout.cancelled → rejected` | суффикс после `.` → словарь |
| id_field | `payout_id` | `id_fields` |
| status_field | `status` | `status_fields` |
| external id | `external_id` | INFO (можно искать операцию и по нему) |

## Amount (T06)

| Что | Значение |
|---|---|
| field | `amount` (корень запроса) |
| unit | `:minor` — description «Сумма в копейках» (маркер `копейк` 0.70) + integer 0.10 + minimum 100000 ≥ 1000 (0.20) → **1.0** |
| multiplier | 100 (RUB → exponent 2) |
| minimum_major | 1000 |
| currency_field / currencies | `currency` / `['RUB']` |
| type | `integer` |
| выражение | `to_minor_units(operation.amount)` → `(operation.amount * 100).round.to_i` |

## Fields (T06)

| Поле провайдера | path | source_expr | required | transform | confidence |
|---|---|---|---|---|---|
| amount | `[amount]` | `to_minor_units(operation.amount)` | true | amount | 0.95 |
| currency | `[currency]` | `operation.currency` | true | — | 0.95 |
| external_id | `[external_id]` | `operation.id.to_s` | true | to_s | 0.95 |
| recipient.type | `[recipient, type]` | `requisite_type` | true | — | 0.95 |
| recipient.phone | `[recipient, phone]` | `operation.payout_requisite.dig(requisite_type, 'phone')` | true | — | 0.9 |
| recipient.bank_code | `[recipient, bank_code]` | `operation.payout_requisite.dig('sbp', 'bank_code')` | **required_if type=sbp** | — | 0.6 → `WARN conditional_required` |
| recipient.bank_name | `[recipient, bank_name]` | `operation.payout_requisite.dig('sbp', 'bank_name')` | false | — | 0.9 |
| recipient.card_number | `[recipient, card_number]` | `operation.payout_requisite.dig('card', 'number')` | **required_if type=card** | — | 0.6 → `WARN conditional_required` |

`requisite_types: ['sbp', 'card']` (enum `Recipient.type`). Необязательные поля в коде — через
`.compact` на Hash реквизитов. Заголовок `Idempotency-Key` → `idempotency_headers(operation)` (INFO не нужен).

## Предупреждения — ровно 6 (3 WARN, 3 INFO, 0 UNSUPPORTED)

| # | Level | code | Сообщение (суть) | hint |
|---|---|---|---|---|
| 1 | WARN | `conditional_required` | recipient.bank_code: required only for type=sbp (from description) | `fields.recipient.bank_code.required_if: {field: type, equals: sbp}` уже применено; проверьте |
| 2 | WARN | `conditional_required` | recipient.card_number: required only for type=card (from description) | аналогично |
| 3 | WARN | `signature_encoding_assumed` | X-NovaPay-Signature: encoding not stated, hex assumed | `webhook.signature_encoding: hex|base64` |
| 4 | INFO | `outside_contract` | POST /payouts/{payout_id}/cancel — generated as `cancel_request` helper | — |
| 5 | INFO | `outside_contract` | GET /balance — generated as `fetch_balance` helper | — |
| 6 | INFO | `duplicate_as_success` | 409 on POST /payouts returns PayoutResponse — treated as idempotent replay | `errors.409.action: reject` чтобы отключить |

Порядок в отчёте: WARN, затем UNSUPPORTED, затем INFO; внутри — порядок обнаружения (roles → auth →
statuses → errors → webhooks → amount → fields). `--strict` → exit 4 (есть WARN).

## Plan (T08)

| Что | Значение |
|---|---|
| provider | `{name: 'novapay', class_name: 'NovapayService', env_prefix: 'NOVAPAY', title: 'NovaPay'}` |
| base_url | `{default: 'https://api.sandbox.novapay.example/v1', production: 'https://api.novapay.example/v1', env_var: 'NOVAPAY_BASE_URL'}` |
| operations | create, status, cancel, balance (webhook отдельно) |
| validations (**4**) | `amount_too_low` (min 1000), `external_id_too_long` (maxLength 64), `phone_invalid` (pattern `^7\d{10}$`), `currency_not_supported` (enum RUB) |
| fixtures | ключи ТЗ: `create_request.{request,response_201,response_422}`, `fetch_status.response_200`, `callback.{payload,expected_operation_status='approved'}`, `callback_failed.{payload,expected_operation_status='rejected'}` + наши: `callback_processing`, `cancel`, `balance`, `errors.{401,429}`, `auth` |
| gateway config | `{"external_method": "sbp_payout", "gateway": "RUB_SBP_WITHDRAW"}` |
| warnings.size | 6 |

`--provider "Nova Pay"` → `NovaPayService`, `NOVA_PAY_BASE_URL`, файл `nova_pay_service.rb`.
Без `--provider` → имя из `info.title` «NovaPay Payout API» минус стоп-слова (api, payout, payouts,
service, rest, v1…) → `novapay`.

## Reference-тест (T10, `spec/reference_spec.rb`)

Сгенерированный `novapay_service.rb` должен содержать: `class NovapayService < BaseService`,
`BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')`, методы
`create_request`, `fetch_status`, `process_callback`, `check_conditions`, `build_payout_payload`,
`verify_signature!`, `rescue Provider::RateLimitError`, `rescue Provider::UnauthorizedError`,
`failure(:too_many_requests, 'provider.rate_limit')`, `failure(:unauthorized, 'provider.invalid_credentials')`,
`failure(:unprocessable_entity, 'amount_too_low')`, `STATUS_MAP` с пятью парами из таблицы статусов,
`ERROR_MAP` со строками 400/401/402/422/429/500, `'X-NovaPay-Signature'`, `'payout.completed'`,
`'payout.failed'`, `approve_operation`, `reject_operation`, `payload.dig('error', 'code')`,
`operation.payout_requisite.dig('sbp', 'phone')`, `'sbp'`, `bank_code`, `bank_name`.

`INTEGRATION.md` должен содержать заголовки и строки таблиц из `spec/reference/novapay/INTEGRATION.md`
(разделы Авторизация, Методы, Маппинг статусов, Обработка ошибок, ProviderGateway config, Webhook signature)
плюс наш раздел «Допущения». `fixtures.json` — все ключи и значения из `spec/reference/novapay/fixtures.json`
являются подмножеством нашего (`deep_subset`).
