# Тестовые спецификации: CardPay, SwiftPay, битые спеки

Зачем читать: универсальность оценивается по коду, но доказывается на спеках, которые отличаются от
NovaPay по каждому измерению (auth, единицы суммы, названия статусов, структура ответа, источник
webhook, подпись, версия OpenAPI, формат файла). Файлы лежат в `examples/specs/` и `spec/fixtures/broken/`;
ниже — что в них заложено и что forge обязан выдать. Любое расхождение чинится в анализаторах и
словарях (`rules/`), **никогда** в шаблонах под конкретный случай.

## 1. Матрица покрытия

| Измерение | NovaPay | CardPay | SwiftPay | Реальные (docs/REAL_SPECS.md) |
|---|---|---|---|---|
| Формат / версия | YAML 3.0.3 | YAML 3.0.3 | **JSON 3.1.0** | YAML/JSON 3.0.0–3.1.0 |
| Серверы | sandbox + prod | **только prod** | server **variables** | разные |
| Auth | apiKey header | **http bearer** | **http basic** (+ oauth2 альтернатива) | basic/bearer, oauth2, apiKey query |
| Реквизиты | СБП (phone, bank_code), card | **карта** (pan, holder, expiry) | **банковский счёт** (iban/bic), `oneOf` | разные |
| Сумма | integer, копейки, minimum | **string "1500.00"**, pattern | **number, multipleOf 0.01** | integer cents, integer kobo, minor units |
| Статусы | pending…cancelled | **NEW/PROCESSING/SUCCESS/DECLINED/ON_HOLD** в поле `state` | **CREATED/PENDING_APPROVAL/SENT/SETTLED/RETURNED/REJECTED** | 100+ camelCase, статусы текстом в description |
| Ответ | плоский `{id, status}` | **обёртка `data`**, `transfer_id`, `state` | плоский | разные |
| Webhook | paths + `security: []` | **`callbacks`** у create | **top-level `webhooks`** (3.1) | нет в спеке |
| Событие | `event` enum с суффиксом | `type` enum | общий `type`, статус в `data.status` | — |
| Подпись | HMAC-SHA256, hex не указан | **HMAC-SHA512 base64**, payload не указан | **с timestamp** → UNSUPPORTED | — |
| Ошибки | `{error: {code}}` | **`{errors: [{code}]}`** | **`application/problem+json`** | разные |
| Cancel | POST …/cancel | **нет** | **DELETE** | POST без path param (Adyen) |
| Idempotency | header uuid | нет | header string | — |
| Прочее | balance | list-эндпоинт, `merchant_id` в теле, `callback_url` в теле | `allOf`, `type: [..., null]`, внешний `$ref` | form-encoded, `~1` в pointer |

## 2. CardPay (`examples/specs/cardpay.yaml`)

Провайдер карточных выплат. Ключевые особенности перечислены в матрице; спека полная и валидная.

### Ожидаемый результат `analyze` без overrides

| Что | Значение |
|---|---|
| Эндпоинтов | 3: `POST /transfers` (create 0.95), `GET /transfers/{transfer_id}` (status 0.90), `GET /transfers` (other: не проходит `requires` status) |
| Auth | `bearer`, `Authorization: Bearer <credentials.token>`, из root `security` |
| Base URL | default = production `https://api.cardpay.example/v2` → `WARN production_default` |
| Статусы | поле `data.state` (0.95): NEW, PROCESSING → in_progress; SUCCESS → approved; DECLINED → rejected; **ON_HOLD → unmapped** |
| Response id | `['data', 'transfer_id']` (0.8, внутри wrapper) |
| Ошибки | 400 validation_error → reject; 401 → alert_block; 403 forbidden → alert_block; 404 (status) → reject; 422 → reject; 500 → retry; 503 unavailable → retry_backoff (`Retry-After`); код из `errors.0.code` |
| Webhook | источник `callbacks.onStateChange` у createTransfer → `INFO webhook_source_callbacks`; URL-выражение `{$request.body#/callback_url}` |
| Подпись | header `X-Signature`; description «HMAC-SHA512 … base64» → sha512/base64; payload не указан → `WARN signature_payload_assumed` (raw_body) |
| События | поле `type`: transfer.settled → approved; transfer.declined → rejected; **transfer.on_hold → unmapped** |
| Webhook id / status | `data.transfer_id` / `data.state` |
| Сумма | `amount` string, pattern `^\d+\.\d{2}$`, description «two decimals» → major 0.9 (0.80 + 0.60 → cap 1.0 → без WARN), `format('%.2f', …)`; без minimum |
| Валюты | `[RUB, USD]` → `SUPPORTED_CURRENCIES = %w[RUB USD]` |
| Поля | `merchant_id` → `credentials.fetch('merchant_id')` (`INFO credential_field`); `reference` → `operation.id.to_s`; `description` → alias; `callback_url` → `callback_url`; `destination.card.pan` → `dig('card', 'number')`; `destination.card.holder` → `dig('card', 'holder')`; **`destination.card.expiry` → unmapped** (формат MM/YY) |
| Requisite types | `['card']` (нет enum типа → из имени контейнера `card`) |
| Cancel | отсутствует → `INFO no_cancel_endpoint`; в сервисе нет `cancel_request` |

**Предупреждения без overrides — 5 WARN, 4 INFO, 0 UNSUPPORTED:**

| Level | code | Суть | hint |
|---|---|---|---|
| WARN | production_default | no sandbox server; default BASE_URL is production | `base_url.default: <sandbox url>` |
| WARN | unmapped_status | ON_HOLD not in status dictionary | `statuses.ON_HOLD: in_progress` |
| WARN | unmapped_event | transfer.on_hold → status on_hold not mapped | `statuses.ON_HOLD: …` (закрывается тем же) |
| WARN | unmapped_field | destination.card.expiry (string MM/YY) has no source | `fields.destination.card.expiry.source: "…"` |
| WARN | signature_payload_assumed | X-Signature: signed payload not stated — raw body assumed | `webhook.signature_payload: raw_body \| fields` |
| INFO | outside_contract | GET /transfers (listTransfers) not used | — |
| INFO | no_cancel_endpoint | no cancel endpoint; cancel_request not generated | — |
| INFO | credential_field | merchant_id → credentials.merchant_id | — |
| INFO | webhook_source_callbacks | webhook taken from callbacks of createTransfer | — |

`--strict` → exit 4.

### С `examples/overrides/cardpay.yml`

Переопределения: `base_url.default`, `statuses.ON_HOLD: in_progress`, `fields.destination.card.expiry.source`,
`webhook.signature_payload: raw_body`. Результат: **0 WARN**, 4 `INFO override_applied` + 4 прежних INFO;
`--strict` → exit 0. Сгенерированный spec cardpay зелёный. Golden: `spec/golden/cardpay/` (без overrides)
и `spec/golden/cardpay_overrides/`.

## 3. SwiftPay (`examples/specs/swiftpay.json`)

Выплаты на банковский счёт (IBAN/SWIFT), OpenAPI 3.1 в JSON.

### Ожидаемый результат `analyze`

| Что | Значение |
|---|---|
| Загрузка | JSON; `servers[0].url` `https://{env}.swiftpay.example/api` с `variables.env.default = sandbox` → `https://sandbox.swiftpay.example/api` (`INFO server_variables`); production — `enum` второй вариант `api` |
| Эндпоинтов | 4: `POST /v1/payments/outbound` (create), `GET /v1/payments/outbound/{payment_id}` (status), `DELETE /v1/payments/outbound/{payment_id}` (cancel, method delete), `GET /v1/accounts/balance` (balance) |
| Auth | root `security: [{basicAuth: []}, {oauth2: [...]}]` → первый поддерживаемый `basic` (login/password); второй → `UNSUPPORTED oauth2_alternative` |
| Схема запроса | `allOf` [BasePayment, {beneficiary, purpose}] → слияние свойств; `beneficiary.oneOf` [IbanBeneficiary, AccountBeneficiary] → первый вариант + `WARN one_of_first_variant` |
| 3.1 типы | `purpose.type: ["string", "null"]` → string, nullable |
| Сумма | `amount` number, `multipleOf: 0.01`, description «major units (e.g. 100.50)» → major 0.9; `to_f.round(2)`; minimum 1 → `MIN_AMOUNT = 1` |
| Статусы | `status` enum: CREATED, SENT → in_progress; SETTLED → approved; REJECTED → rejected; **PENDING_APPROVAL, RETURNED → unmapped** |
| Ошибки | `application/problem+json` (`{type, title, status, detail, code}`) — media type принимается; код из `code` |
| Webhook | top-level `webhooks.paymentStatusChanged` → `INFO webhook_source_webhooks`; событие `type` без enum (общее `payment.status_changed`) → `event_map: {}`, статус из `data.status`; id `data.payment_id` |
| Подпись | header `Swift-Signature`, description «t=<timestamp>,v1=<hex>» → `UNSUPPORTED signature_with_timestamp` → `verify_signature!` бросает `NotImplementedError` с TODO |
| Внешний `$ref` | в ответе balance: `https://schemas.swiftpay.example/common/Money.json` → `UNSUPPORTED external_ref` (схема → `{}`), генерация продолжается |
| Поля | `reference` → id; `amount`, `currency`; `purpose` → description; `beneficiary.iban` → `dig('bank_account', 'iban')`; `beneficiary.bic` → `dig('bank_account', 'bic')`; `beneficiary.name` → holder; **`beneficiary.address` (object: country, city, line1) → unmapped** |
| Requisite types | `['bank_account']` |
| Idempotency | header `Idempotency-Key` (string) |

**Предупреждения — 4 WARN, 3 UNSUPPORTED (INFO — не фиксируем числом):**
WARN `one_of_first_variant`, `unmapped_status PENDING_APPROVAL`, `unmapped_status RETURNED`,
`unmapped_field beneficiary.address`; UNSUPPORTED `external_ref`, `signature_with_timestamp`, `oauth2_alternative`.
Exit 0 (UNSUPPORTED не фатальны: не затрагивают create-запрос). Сгенерированный spec swiftpay зелёный,
пример на подпись помечен `pending` («signature with timestamp is not generated»).

Внешний `$ref` в **схеме запроса create** (другой файл, `spec/fixtures/broken/external_ref_in_create.yaml`)
→ фатально: `UnsupportedError`, exit 1.

### С `examples/overrides/swiftpay.yml`

`statuses.PENDING_APPROVAL: in_progress`, `statuses.RETURNED: rejected`, `fields.beneficiary.address.source`
→ остаётся 1 WARN (`one_of_first_variant` — нельзя закрыть overrides, только выбрать вариант через
`fields.beneficiary.variant: IbanBeneficiary` — реализовать, если хватит времени) и 3 UNSUPPORTED.

## 4. Битые спеки (`spec/fixtures/broken/`) — T02, T07, T12

| Файл | Что сломано | Ошибка | Сообщение содержит | Exit |
|---|---|---|---|---|
| `not_yaml.yaml` | `{{{ not: [yaml` | `SpecError` | `cannot parse`, имя файла | 1 |
| `empty.yaml` | пустой файл | `SpecError` | `empty document` | 1 |
| `not_object.yaml` | `- just\n- a list` | `SpecError` | `root must be an object` | 1 |
| `swagger2.yaml` | `swagger: '2.0'` | `SpecError` | `Swagger 2.0 is not supported; convert to OpenAPI 3` | 1 |
| `no_openapi_key.json` | нет `openapi` | `SpecError` | `missing 'openapi'` | 1 |
| `no_paths.yaml` | `paths: {}` | `SpecError` | `no paths` | 1 |
| `bad_ref.yaml` | `$ref: '#/components/schemas/Missing'` | `SpecError` | `unresolved $ref`, pointer `#/paths/~1payouts/post/requestBody/...` | 1 |
| `cyclic_ref.yaml` | A → B → A | `SpecError` | `circular $ref`, цепочка | 1 |
| `external_ref_in_create.yaml` | `$ref: 'other.yaml#/X'` в схеме запроса create | `UnsupportedError` | `external $ref`, pointer | 1 |
| `no_create.yaml` | только `GET /payouts/{id}` и `GET /balance` | `GenerationError` | `no create endpoint`, hint `endpoints.<operationId>: create` | 2 (`analyze` — exit 0 с WARN `no_create_endpoint`) |

Плюс проверки CLI: файл не существует → exit 1 `file not found`; `--lang python` → exit 1 `only ruby is
supported`; повторный `generate` в непустой `--out` без `--force` → exit 2; `--strict` при WARN → exit 4;
`--debug` печатает стектрейс.

## 5. Как чинить расхождения

1. Роль не распознана → слово в `endpoint_roles.yml` или новый сигнал в `EndpointRoles`.
2. Статус не сопоставлен → если общеупотребительный — в `status_map.yml`; если двусмысленный — остаётся WARN (это правильно).
3. Поле не сопоставлено → алиас в `field_aliases.yml`; если специфично для провайдера — остаётся WARN + overrides.
4. Шаблон «не умеет» вариант (нет cancel, нет webhook, bearer) → ветка в шаблоне по полю плана, никогда по имени провайдера.
5. После каждого исправления — golden NovaPay остаётся байт-в-байт прежним (или дифф осознанно принят).
