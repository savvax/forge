# Правила и словари (`rules/*.yml`) и `overrides.yml`

Зачем читать: здесь живёт всё «платёжное знание» forge. Ruby-код анализаторов — это общий движок
подсчёта очков; конкретные слова, статусы и коды — только здесь. Добавить провайдера с новыми
названиями = дописать строку в словарь, не трогая Ruby.

## 0. Общие правила движка

- Загрузка: `Forge::Rules.load(dir = 'rules')` один раз, результат `frozen`. `--rules-dir` не нужен —
  расширение через `overrides.yml` (§ 9). Отсутствие файла словаря → `GenerationError` с подсказкой.
- Нормализация слов: `downcase`, `-`/пробел/`.` → `_`, camelCase → snake_case (`approvalPending` →
  `approval_pending`), обрезка префиксов ролей (`payout.completed` → `completed`, `transfer_success` → `success`).
- Confidence ∈ [0.0, 1.0]. Пороги в `thresholds.yml`: `accept: 0.8` (без WARN), `warn: 0.5`
  (принято + `WARN low_confidence`), ниже — не принято, `WARN needs_override` + безопасная заглушка.
- Каждый `Finding.source` — человекочитаемое объяснение решения (попадает в `report.txt` и раздел
  «Допущения» `INTEGRATION.md`): `"operationId 'createPayout' matches /create/; POST /payouts without path param"`.

## 1. `thresholds.yml`

```yaml
accept: 0.8
warn: 0.5
```

## 2. `endpoint_roles.yml` — роли эндпоинтов

Для каждого эндпоинта считается очко по каждой роли. Роль эндпоинта — максимальное очко, если оно
≥ `warn` и пройдены `requires`. Один эндпоинт — одна роль; на одну роль — один эндпоинт (побеждает
большее очко, при равенстве — первый в порядке `paths`; проигравший → `other` + `WARN role_conflict`
с подсказкой `endpoints.<operationId>: <role>`).

```yaml
# Слова ищутся в path (сегменты), operationId, summary, tags — после нормализации.
payout_words: [payout, payouts, withdraw, withdrawal, withdrawals, transfer, transfers, disburse,
               disbursement, disbursements, send, remittance, outbound]
weak_payout_words: [payment, payments]   # слово выплаты, только если в спеке нет путей с сильным словом;
                                         # иначе create-кандидат на пути без сильного слова получает −0.5
# status/cancel принимаются, только если в пути есть слово выплаты или путь лежит под create-эндпоинтом:
# в спеке без выплат (pay-in) GET /x/{id} иначе набирал 0.65 и становился status.
# status/cancel принимаются, только если в пути есть слово выплаты или путь лежит под create-эндпоинтом:
# в спеке без выплат (pay-in) GET /x/{id} иначе набирал 0.65 и становился status.
negative_words: [order, orders, inventory, subscription, subscriptions, booking, bookings, invoice,
                 invoices, terminal, loyalty, climate, test_helpers, refund, refunds, recipient,
                 recipients, otp, export, bulk, search, resend, finalize,
                 simulate, simulation, inward, incoming, payin, deposit, deposits, health,
                 calculate, estimate, validate, preview, link, links, methods]   # каждое совпадение: −0.5

roles:
  create:
    requires: { has_request_body: true }
    signals:
      method_post: 0.30
      payout_word_in_path: 0.25
      create_word: 0.20              # create, new, submit, send, initiate, make, register, request, initiat, post
      no_path_param: 0.10
      has_request_body: 0.10
  status:
    requires: { any: [has_path_param, id_query_param] }   # id_query_param: query-параметр с id/code/reference в имени
    signals:
      method_get: 0.30
      payout_word_in_path: 0.25
      has_path_param: 0.20
      status_word: 0.15              # status, get, retrieve, fetch, info, details, show, verify, check
      array_response: -0.40          # 2xx-схема — массив: это список, а не статус одной выплаты
      multi_path_param: -0.30        # больше одного {param} в пути: из operation берётся только один id
  cancel:
    requires: { any: [has_path_param, has_request_body] }
    signals:
      method_post_or_delete: 0.25
      payout_word_in_path: 0.20
      cancel_word_in_path: 0.30      # cancel, void, revoke, abort, stop
      cancel_word_in_operation: 0.10
      has_path_param: 0.10
      multi_path_param: -0.30
  webhook:
    signals:
      webhook_word_in_path: 0.40     # webhook, webhooks, callback, callbacks, notify, notification, notifications, ipn, events
      security_explicitly_empty: 0.20
      signature_header_param: 0.20   # header-параметр с sign/signature/hmac/digest в имени
      method_post: 0.10
    explicit_sources_confidence: 0.95  # найден через callbacks или top-level webhooks
    min_confidence: 0.6                # слово в пути + POST (0.5) — управление подписками (POST /v1/webhook_endpoints), не callback:
                                       # роль не назначается, WARN webhook_rejected с подсказкой endpoints.<operationId>: webhook
  balance:
    signals:
      balance_word_in_path: 0.50     # balance, balances, account, wallet, funds
      method_get: 0.25
      no_path_param: 0.10
```

Проверка на NovaPay: create 0.95, status 0.90, cancel 0.95, webhook 0.90, balance 0.85
(разбор в `docs/SPEC_ANALYSIS_NOVAPAY.md`). `GET /payouts` (список): status требует path-параметр →
не проходит `requires` → `other`.

Ограничение области: `--include-paths GLOB` (CLI) или `paths.include: ['/v1/payouts*']` (overrides)
оставляет в анализе только совпавшие пути. Обязательно для больших спек (Stripe — 419 путей).

## 3. `status_map.yml` — статусы

```yaml
# Внутренние статусы Space Payments: in_progress | approved | rejected. Канон из ТЗ — первые строки.
in_progress: [pending, processing, in_progress, new, created, accepted, queued, submitted, initiated,
              sent, scheduled, authorized, authorised, in_transit, booked, awaiting, received, started]
approved:    [completed, complete, success, succeeded, successful, approved, done, paid, settled,
              captured, confirmed, executed, finished, ok, credited]
rejected:    [failed, failure, fail, error, rejected, declined, cancelled, canceled, expired, refused,
              denied, void, voided, aborted, blocked, timeout, unsuccessful]
# Намеренно НЕ в словаре (неоднозначно → WARN unmapped_status → overrides):
#   on_hold, manual_review, returned, reversed, refunded, unclaimed, unknown, pending_approval, approval_pending
status_fields: [status, state, payout_status, transfer_status, payment_status, transaction_status, result, batch_status]
id_fields:     [id, payout_id, transfer_id, payment_id, transaction_id, reference_id, uuid, code]
wrappers:      [data, result, payout, transfer, payment, response, transaction]
```

Алгоритм `Statuses`:
1. Найти в схеме ответа status-эндпоинта (иначе create) свойство с именем из `status_fields`, у которого
   есть `enum` → `field_path`, confidence 0.95.
2. Нет `enum`, но в `description` поля есть слова в обратных кавычках/кавычках (`` `paid`, `pending` ``) →
   значения из description, confidence 0.6 → `WARN status_from_description`. (Так у Stripe.)
3. Каждое значение → нормализация → словарь. Не найдено → `unmapped` + `WARN unmapped_status` с
   подсказкой `statuses.<VALUE>: in_progress|approved|rejected`.
4. Результат: `{field_path:, map:, unmapped:, source:}`.

Response id: `id` в корне → 0.95; `*_id`/из `id_fields` в корне → 0.85; внутри `wrappers` (глубина ≤ 2) →
0.8; не найдено → `['id']` + `WARN response_id_not_found`.

## 4. `error_actions.yml` — ошибки

```yaml
# action: reject | retry | retry_backoff | alert | alert_block | treat_as_success
http:
  400: { internal_code: validation_error,   action: reject }
  401: { internal_code: invalid_credentials, action: alert_block }
  402: { internal_code: insufficient_balance, action: retry }
  403: { internal_code: forbidden,           action: alert_block }
  404: { internal_code: not_found,           action: reject }
  409: { internal_code: conflict,            action: reject }
  422: { internal_code: validation_error,    action: reject }
  429: { internal_code: rate_limit,          action: retry_backoff }
  500: { internal_code: internal_error,      action: retry }
  502: { internal_code: internal_error,      action: retry }
  503: { internal_code: unavailable,         action: retry_backoff }
  504: { internal_code: internal_error,      action: retry }
codes:   # код провайдера (нормализованный) → уточнение
  validation_error:      { internal_code: validation_error,    action: reject }
  invalid_request:       { internal_code: validation_error,    action: reject }
  unauthorized:          { internal_code: invalid_credentials, action: alert_block }
  invalid_api_key:       { internal_code: invalid_credentials, action: alert_block }
  insufficient_balance:  { internal_code: insufficient_balance, action: retry }
  insufficient_funds:    { internal_code: insufficient_balance, action: retry }
  recipient_not_found:   { internal_code: recipient_invalid,   action: reject }
  invalid_recipient:     { internal_code: recipient_invalid,   action: reject }
  bank_unavailable:      { internal_code: bank_unavailable,    action: retry }
  amount_limit_exceeded: { internal_code: limit_exceeded,      action: reject }
  rate_limit_exceeded:   { internal_code: rate_limit,          action: retry_backoff }
  duplicate:             { internal_code: duplicate,           action: treat_as_success }
  invalid_status:        { internal_code: invalid_status,      action: reject }
  not_found:             { internal_code: not_found,           action: reject }
  internal_error:        { internal_code: internal_error,      action: retry }
error_code_paths: [error.code, code, errors.0.code, error_code, type, title]   # где искать код в теле ошибки
retry_after_headers: [Retry-After, X-RateLimit-Reset, RateLimit-Reset]
```

Алгоритм `Errors`: для всех ответов create/status/cancel со статусом ≥ 400 — код провайдера из
`example`/`examples` (по `error_code_paths`) или первого `enum` у поля `code`; действие — `codes` → иначе
`http`. Если схема ответа ≥ 400 совпадает со схемой успеха (тот же `x-forge-ref-name`) → `action:
treat_as_success` + `INFO duplicate_as_success` (NovaPay 409). `Retry-After` в headers → `retry_after_header`.
Все `enum` кодов схемы ошибки → `codes: [...]` для `INTEGRATION.md`.

## 5. `amount_units.yml` — единицы суммы

```yaml
minor_markers: [копейк, копеек, коп., cents, cent, minor unit, minor_unit, minor units, smallest unit,
                subunit, kopeck, kopecks, kobo, pence, centavo, öre, ore, tiyn, тиын, "x100", "×100", "1/100"]
major_markers: [рубл, rubles, major unit, major units, in dollars, two decimals, decimal, "100.50", "10.00", формат 0.00]
signals:
  minor_marker_in_description: 0.70
  integer_type: 0.10
  integer_with_minimum_ge_1000: 0.20     # минимум ≥ 1000 в целых — почти наверняка минорные единицы
  major_marker_in_description: 0.60
  decimal_pattern: 0.80                  # string с pattern ^\d+\.\d{2}$ и похожие
  multiple_of_cent: 0.60                 # number с multipleOf 0.01
  number_type: 0.20
default: { unit: major, confidence: 0.4, warning: amount_unit_assumed }
```

Результат: `{field:, unit: :minor|:major, multiplier:, minimum_major:, currency_field:, currencies:, type:, source:}`.
`multiplier` = 10^exponent валюты из `currency_exponents.yml` (первая валюта enum; нет → 2).
`minimum_major` = `minimum / multiplier` для minor, `minimum` для major. Поле суммы ищется по алиасу
`amount` (§ 7), в т. ч. вложенное (`amount.value`, `money.amount`).

## 6. `currency_exponents.yml`

```yaml
default: 2
JPY: 0
KRW: 0
VND: 0
CLP: 0
ISK: 0
KWD: 3
BHD: 3
JOD: 3
OMR: 3
TND: 3
```

## 7. `field_aliases.yml` — поля запроса

Каждое свойство схемы запроса create → выражение на стороне `operation`. Совпадение по нормализованному
имени свойства; для вложенных объектов — по имени родителя (`recipient`, `destination`, `beneficiary`,
`receiver`, `payee`, `account`, `card`, `bank`) и по «хвосту» пути (`destination.card.pan` → `pan`).

```yaml
amount:        { names: [amount, sum, total, value, money.amount, amount.value, money.value],
                 expr: "%{amount_expr}", transform: amount }   # выражение подставляет Amount-анализатор
currency:      { names: [currency, currency_code, ccy, amount.currency, money.currency], expr: "operation.currency" }
external_id:   { names: [external_id, merchant_order_id, order_id, reference, client_reference, request_id,
                         tx_id, transaction_id, merchant_reference, merchant_tx_id, external_reference, client_id],
                 expr: "operation.id.to_s", transform: to_s }
description:   { names: [description, purpose, comment, narrative, note, memo, statement_descriptor, reason],
                 expr: "operation.description || \"Payout #{operation.id}\"" }
idempotency:   { names: [idempotency_key, idempotence_key, nonce], expr: "operation.idempotency_key" }
callback_url:  { names: [callback_url, webhook_url, notify_url, notification_url, ipn_url], expr: "callback_url" }
credential:    { names: [merchant_id, shop_id, account_id, terminal_id, partner_id, seller_id, source],
                 expr: "credentials.fetch('%{name}')", info: credential_field }   # source: у Paystack = 'balance'
requisite_container: [recipient, receiver, beneficiary, destination, payee, account, target, details, card, bank, bank_account]
requisite_type:      { names: [type, method, payout_method, payment_method, channel, kind, destination_type],
                       expr: "requisite_type" }
requisite_fields:    # хвост пути → поле реквизита; тип берётся из варианта (sbp/card/bank_account/wallet)
  phone:          { names: [phone, phone_number, msisdn, mobile, mobile_number], field: phone }
  bank_code:      { names: [bank_code, bic, bank_id, bank_bic, member_id, bank_identifier, routing_number, sort_code], field: bank_code }
  bank_name:      { names: [bank_name, bank], field: bank_name }
  number:         { names: [card_number, pan, number, card, card_pan], field: card_number, types: [card] }
  holder:         { names: [holder, cardholder, card_holder, name, full_name, account_holder, beneficiary_name, holder_name], field: holder }
  expiry_month:   { names: [expiry_month, exp_month, month], field: expiry_month, types: [card] }
  expiry_year:    { names: [expiry_year, exp_year, year], field: expiry_year, types: [card] }
  account_number: { names: [account_number, account, account_no, acct], field: account_number, types: [bank_account] }
  iban:           { names: [iban], field: iban, types: [bank_account] }
  bic:            { names: [bic, swift, swift_code, swift_bic], field: bic, types: [bank_account] }
  country:        { names: [country, country_code], field: country }
  wallet_id:      { names: [wallet_id, wallet, account_id], field: id, types: [wallet] }
customer_fields:
  email: { names: [email, customer_email, payer_email], expr: "operation.customer&.dig('email')" }
  ip:    { names: [ip, ip_address, customer_ip], expr: "operation.customer&.dig('ip')" }
conditional_required_patterns:   # regex по description → required_if
  - "(?:for|when|if|при|для)\\s+(?<field>\\w+)\\s*=\\s*(?<value>\\w+)"
  - "required\\s+(?:only\\s+)?(?:for|when)\\s+(?<field>\\w+)\\s+(?:is|=)\\s*(?<value>\\w+)"
```

Алгоритм `Fields`: для каждого свойства запроса → `FieldMapping(provider_field, path, source_expr,
required, transform, schema, confidence)`. Обязательность — из `required` схемы; условная — из
`conditional_required_patterns` в `description` (confidence 0.6 → `WARN conditional_required`, поле
попадает только в вариант `requisite_type == value`). Неизвестное свойство → `source_expr: nil`,
`# TODO(forge): map '<path>'` в коде, `WARN unmapped_field` с подсказкой `fields.<path>.source: "…"`.
Массивы (`items`) → `WARN array_field_unsupported`, в код — `[]` + TODO. Вложенные объекты, не
являющиеся `requisite_container`, разворачиваются рекурсивно с префиксом.

## 8. `webhook_signature.yml`

```yaml
header_markers:  [sign, signature, hmac, digest, x-hub-signature]
algorithm_regex: "HMAC[-_ ]?(SHA[-_]?(256|512|1))"       # группа 2 → sha256 | sha512 | sha1
encoding:
  hex:    [hex, hexdigest, hexadecimal, hex-encoded]
  base64: [base64, b64, base-64]
payload:
  raw_body: [body, тела, тело, payload, raw, request body]
  fields:   [concatenat, конкатен, joined, fields, параметров, "+"]
timestamp_markers: ["t=", timestamp, "v1=", nonce, "signed_payload"]   # → UNSUPPORTED signature_with_timestamp
secret_credential_key: callback_secret
event_fields:  [event, type, event_type, name, action, topic]
defaults: { algorithm: sha256, encoding: hex, payload: raw_body }
signals:
  header_found: 0.40
  algorithm_in_description: 0.30
  encoding_in_description: 0.15
  payload_in_description: 0.15
```

Алгоритм `Webhooks`: источник — эндпоинт роли `webhook` из `paths`, иначе `callbacks` create-эндпоинта,
иначе top-level `webhooks` (3.1). Подпись: header-параметр по `header_markers`; алгоритм/кодировка/payload
из `description` заголовка и операции. Не указано → default + `WARN signature_encoding_assumed` /
`signature_payload_assumed` (по одному на каждое допущение). `timestamp_markers` → `UNSUPPORTED
signature_with_timestamp` (в коде `verify_signature!` бросает `NotImplementedError` с TODO).
События: поле из `event_fields` с `enum` → каждое значение → суффикс после `.`/`_` → словарь статусов
→ `event_map`; нет `enum` (общий тип события) → `event_map: {}` и статус берётся из `status_field`.
`id_field` — по `id_fields` (в т. ч. внутри `wrappers`: `data.transfer_id`).

## 9. `overrides.yml` — переопределения пользователя

Общий механизм (подтверждён организаторами). Каждое применённое переопределение → `INFO override_applied`.
Неизвестный ключ → `SpecError` с «did you mean …» (`DidYouMean::SpellChecker`).

```yaml
provider:
  name: cardpay                 # имя файла/ENV; иначе из --provider или info.title
  class_name: CardPayService    # иначе из name
paths:
  include: ['/transfers*']      # ограничить анализ (glob по path)
base_url:
  default: https://sandbox.cardpay.example/v2
  production: https://api.cardpay.example/v2
  env_var: CARDPAY_BASE_URL
endpoints:                      # operationId → create | status | cancel | balance | webhook | other
  createTransfer: create
  listTransfers: other
auth:
  type: bearer                  # api_key | bearer | basic
  header: Authorization
  prefix: "Bearer "
  credential_key: token
statuses:                       # провайдерский статус → внутренний
  ON_HOLD: in_progress
events:                         # событие webhook → внутренний статус
  transfer.on_hold: in_progress
amount:
  unit: major                   # minor | major
  multiplier: 100
  minimum_major: 10
fields:                         # путь поля запроса → правила
  destination.card.expiry:
    source: "format('%02d/%02d', operation.payout_requisite.dig('card', 'expiry_month'), operation.payout_requisite.dig('card', 'expiry_year') % 100)"
  recipient.bank_code:
    required: true
    required_if: { field: type, equals: sbp }
webhook:
  signature_header: X-Signature
  signature_algorithm: sha512   # sha256 | sha512 | sha1
  signature_encoding: base64    # hex | base64
  signature_payload: raw_body   # raw_body | fields
  event_field: type
  id_field: data.transfer_id
  status_field: data.state
errors:
  409: { action: reject, internal_code: duplicate }
  bank_unavailable: { action: retry }
```

Порядок применения: findings → overrides (поле за полем) → валидации → фикстуры. Overrides не могут
добавить эндпоинт, которого нет в спеке (только переназначить роль).

## 10. Как добавить новое правило (для README → «Расширение»)

1. Новый синоним статуса/поля/слова роли — строка в соответствующем `rules/*.yml` + пример в `spec/rules/`.
2. Новый тип сигнала (например, `x-payout: true` у эндпоинта) — метод в анализаторе + вес в словаре.
3. Новый вид переопределения — ключ в `Plan::Overrides::SCHEMA` + документация в этом файле.
4. Новый выходной файл — рендерер + шаблон + строка в `docs/OUTPUT_FORMAT.md`; `--templates-dir` позволяет
   подменить любой шаблон без изменения кода.
