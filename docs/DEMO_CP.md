# Демо CP3 — прогон в чистом клоне (6.09, 7 минут)

Клон: `git clone . tmp/cp-clone` + незакоммиченный дифф рабочего дерева (`git apply`) + отчёты
`examples/real/reports/`. Ruby 3.3.12, `bundle install` — ок. Всё, что ниже, — реальный вывод.

**Что не работает: ничего в проекте.** Единственный сбой — первый `docker build` упал на сети
(`TLS handshake timeout` при загрузке `ruby:3.3-slim`), повтор собрался. Перед чек-поинтом собрать
образ заранее, на демо показывать `docker run`, а не `build`.

**Важно до чек-поинта:** в рабочем дереве 21 изменённый файл и 26 новых отчётов (вторая волна из 13
реальных спек, правки эвристик ролей/суммы). Всё зелёное — закоммитить, иначе демо из клона репозитория
покажет старое состояние.

## Сценарий и вывод

### 1. `bundle exec rake check` (клон)

```
115 files inspected, no offenses detected
257 examples, 0 failures
Line Coverage: 97.89% (2688 / 2746)
Branch Coverage: 84.41% (937 / 1110)
guard:vendor ok
```
≈ 14 с. Также: `rake determinism` → `determinism ok (30 files)`, `rake readme:check ok (4 commands)`,
`rake licenses ok (52 gems)`.

### 2. `bin/forge analyze --spec examples/specs/novapay.yaml` — 0.6 с, exit 0

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

### 3. `bin/forge generate --spec examples/specs/novapay.yaml --out tmp/demo/novapay --force` — 0.4 с, exit 0

Тот же отчёт, затем:
```
Generating service...
Generating integration guide...
Generating test fixtures...
Generating service spec...
Generating extras...
Generating mock server...
Verifying generated code... ok (ruby -c ×4, rspec 15 examples, 0 failures)
Output:
  ./tmp/demo/novapay/novapay_service.rb
  ./tmp/demo/novapay/INTEGRATION.md
  ./tmp/demo/novapay/fixtures.json
  ./tmp/demo/novapay/novapay_service_spec.rb
  ./tmp/demo/novapay/novapay_extras.rb
  ./tmp/demo/novapay/mock_server.rb
  ./tmp/demo/novapay/report.txt
…
Done: 7 files, 3 warnings, 0 unsupported. Exit 0.
```

### 4. `bundle exec rspec -I lib -I tmp/demo/novapay tmp/demo/novapay/novapay_service_spec.rb` — 0.4 с

```
Provider::NovapayService
  #check_conditions
    rejects amount below minimum
    accepts the fixture operation
  #create_request
    creates payout (201)
    maps 422 to provider.validation_error
    refuses an operation without a known requisite type
    accepts the flat card form of payout_requisite
    maps 401 to invalid_credentials
    maps 429 to rate_limit with retry_after
    maps 5xx to provider.unavailable
    delegates status request_method to fetch_status
  #fetch_status
    maps the provider status to approved
  #process_callback
    approves on payout.completed with valid signature
    rejects on payout.failed
    fails on invalid signature
  NovapayExtras#cancel_request
    cancels a pending payout

15 examples, 0 failures
```

### 5. `bin/e2e examples/specs/novapay.yaml` — 0.7 с, exit 0

```
• generated novapay into tmp/e2e/novapay
• mock up on :58757, webhook receiver on :58756
• check_conditions ok
• create_request ok → provider id novapay_1, status in_progress
• fetch_status ok → in_progress (pending)
• webhook received: POST /webhook HTTP/1.1
operation approved ✓ (novapay)
```

`bin/e2e examples/specs/raiffeisen.yaml` (реальная спека Райффайзенбанка, СБП):
```
• create_request ok → provider id raiffeisen_1, status in_progress
• fetch_status ok → in_progress (IN_PROGRESS)
• webhook received: POST /webhook HTTP/1.1
operation approved ✓ (raiffeisen)
```

### 6. CardPay: `--strict` без overrides → exit 4, с overrides → exit 0

`bin/forge generate --spec examples/specs/cardpay.yaml --out tmp/demo/cardpay --force --strict`
```
Warnings (5):
  WARN         production_default         no sandbox server; default BASE_URL is production (https://api.cardpay.example/v2)
        hint: base_url.default: <sandbox url>  (overrides.yml)
  WARN         unmapped_status            status 'ON_HOLD' (on_hold) of data.state is unknown
        hint: statuses.ON_HOLD: in_progress|approved|rejected  (overrides.yml)
  WARN         signature_payload_assumed  X-Signature: payload not stated; raw_body assumed
        hint: webhook.signature_payload: raw_body|fields  (overrides.yml)
  WARN         unmapped_event             webhook event 'transfer.on_hold' → status 'on_hold' unknown
        hint: events.transfer.on_hold: in_progress|approved|rejected  (overrides.yml)
  WARN         unmapped_field             destination.card.expiry (string, Expiry in MM/YY format) has no source
        hint: fields.destination.card.expiry.source: "…"  (overrides.yml)
Info (4): …
Done: 6 files, 5 warnings, 0 unsupported. Exit 4. (--strict: warnings present, output still generated)
```

`… --overrides examples/overrides/cardpay.yml --strict`
```
Verifying generated code... ok (ruby -c ×3, rspec 13 examples, 0 failures)
Info (8):
  INFO         override_applied           statuses.ON_HOLD → in_progress
  INFO         override_applied           webhook → signature_payload
  INFO         override_applied           fields.destination.card.expiry → source
  INFO         override_applied           base_url → default, production
  …
Done: 6 files, 0 warnings, 0 unsupported. Exit 0.
```

### 7. SwiftPay (OpenAPI 3.1 JSON): UNSUPPORTED без падения — exit 0

```
Verifying generated code... ok (ruby -c ×4, rspec 12 examples, 0 failures, 1 pending)
Warnings (4): unmapped_status PENDING_APPROVAL, unmapped_status RETURNED,
              one_of_first_variant beneficiary (IbanBeneficiary, AccountBeneficiary), unmapped_field beneficiary.address
Unsupported (3):
  UNSUPPORTED  oauth2_alternative         alternative security scheme 'oauth2' (oauth2) is ignored
  UNSUPPORTED  signature_with_timestamp   Swift-Signature: signature includes a timestamp/nonce; verify is a TODO
  UNSUPPORTED  external_ref               GET /v1/accounts/balance: external $ref → {} …
Done: 7 files, 4 warnings, 3 unsupported. Exit 0.
```

### 8. Ошибки разбора — понятные, с pointer и hint

| Файл | Сообщение | exit |
|---|---|---|
| `cyclic_ref.yaml` | `error: circular $ref: #/components/schemas/A -> #/components/schemas/B -> #/components/schemas/A at #/paths/~1payouts/post/requestBody/b/a in …` `hint: break the cycle in the request schema: inline one side or drop the back-reference` | 1 |
| `swagger2.yaml` | `error: Swagger 2.0 is not supported; convert to OpenAPI 3 at #/swagger in …` `hint: use swagger2openapi or similar` | 1 |
| `bad_ref.yaml` | `error: unresolved $ref '#/components/schemas/Missing' in the create request schema at #/paths/~1payouts/post/requestBody/ …` | 1 |
| `not_yaml.yaml` | `error: cannot parse: … at line 1 column 10 in …` `hint: the file must be valid YAML or JSON` | 1 |
| `no_create.yaml` (generate) | `error: no create endpoint found in the spec in …` `hint: set endpoints.<operationId>: create (overrides.yml)` | 2 |

Также: `empty.yaml`, `no_openapi_key.json`, `no_paths.yaml`, `not_object.yaml`, `external_ref_in_create.yaml` — exit 1 с hint.

### 9. Реальные API (основное дерево, `examples/real/` не в git)

`bin/forge analyze --spec examples/real/stripe.json --include-paths '/v1/payouts*'` — 8 МБ, 594 эндпоинта, **0.33 с**:
```
  create   POST /v1/payouts                           PostPayouts              confidence 0.95
  status   GET /v1/payouts/{payout}                   GetPayoutsPayout         confidence 0.90
  cancel   POST /v1/payouts/{payout}/cancel           PostPayoutsPayoutCancel  confidence 0.95   (outside contract → cancel_request)
Auth: basicAuth (basic, header: Authorization) → credentials.login/password
Statuses (status): pending, in_transit → in_progress; paid → approved; canceled, failed → rejected
Amount: integer, minor units (×100) — source: amount (integer) → minor units: 'A positive integer in cents representing how much to payout.'
Done: 11 warnings, 1 unsupported. Exit 0.
```
Сводка по 20 спекам — `examples/real/reports/SUMMARY.md`: 19 × exit 0, GOV.UK Pay — честный exit 1 (Swagger 2.0).

### 10. `bin/integrate --spec examples/specs/novapay.yaml --provider novapay --lang ruby` — exit 0, `output/novapay/` 8 файлов
### 11. `bin/demo --fast` — 2.2 с всё вместе (analyze → generate → rspec → e2e → ls)
### 12. Docker: `docker build -t forge .` (ок со второй попытки), `docker run --rm forge analyze --spec examples/specs/novapay.yaml` → `Done: 3 warnings, 0 unsupported. Exit 0.`
