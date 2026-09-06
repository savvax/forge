# Реальные спецификации провайдеров

Зачем читать: эксперты сказали прямо — «найдите открытые спеки платёжных провайдеров и проверьте на
них». Это самое дешёвое доказательство универсальности и самый честный источник багов загрузчика.
Ссылки ниже **проверены 4.09.2026** (HTTP 200). Спеки не коммитим (размер, лицензии) — скачиваем
`rake real:fetch` в `examples/real/` (в `.gitignore`); коммитим только отчёты `examples/real/reports/*.txt`.

## 1. Корпус

| # | Провайдер / API | URL (raw) | Формат | Размер | Auth | Что интересного |
|---|---|---|---|---|---|---|
| 1 | **Adyen Payout API v68** | `https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/PayoutService-v68.json` | JSON 3.1.0 | 117 КБ | apiKey `X-API-Key` + basic | тот же заголовок, что у NovaPay; `POST /payout` без слова create; **нет status-эндпоинта и webhook**; `amount.value` в minor units; 6 путей (`/confirmThirdParty`…) |
| 2 | **Adyen Transfers API v4** | `https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/TransferService-v4.json` | JSON 3.1.0 | 246 КБ | apiKey header, basic, **apiKey в query** (`clientKey`) | `POST /transfers`, `GET /transfers/{id}`, **`POST /transfers/cancel` без path param**, статусов в enum > 100 в camelCase (`approvalPending`, `booked`…) |
| 3 | **PayPal Payouts v1.9** | `https://raw.githubusercontent.com/paypal/paypal-rest-api-specifications/main/openapi/payments_payouts_batch_v1.json` | JSON 3.0.3 | 74 КБ | **oauth2** | `POST /v1/payments/payouts` (**batch: массив items**), `GET /v1/payments/payouts/{id}`, cancel на payout-item; sandbox + prod серверы |
| 4 | **Paystack** | `https://raw.githubusercontent.com/PaystackHQ/openapi/master/dist/paystack.yaml` | YAML 3.0.1 | 125 КБ | bearer (root security) | `POST /transfer` (`transfer_initiate`), `GET /transfer/{code}`, `GET /transfer/verify/{reference}`, `GET /balance`; **два media type** (form + json); `$ref` на **path-pointer с `~1`**; сумма в kobo |
| 5 | **Stripe** | `https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.json` (не yaml — 6 МБ, Psych медленный) | JSON 3.0.0 | ~6 МБ | basic + bearer (root) | 419 путей → **обязателен `--include-paths '/v1/payouts*'`**; `POST /v1/payouts`, `GET /v1/payouts/{payout}`, `POST /v1/payouts/{payout}/cancel`, `/reverse`; **form-urlencoded** тела; amount «integer in cents»; **статусы без enum, текстом в description** (`paid`, `pending`, `in_transit`, `canceled`, `failed`); webhook'ов в спеке нет |
| 6 | **Square** | `https://raw.githubusercontent.com/square/connect-api-specification/master/api.json` | JSON 3.0.0 | большая | oauth2 + apiKey `Authorization` | `GET /v2/payouts`, `GET /v2/payouts/{payout_id}` — **нет create** → ожидаем `GenerationError` (exit 2); ловушка: `POST /v2/transfer-orders` (складские заказы) — проверка `negative_words` |
| 7 | **Plaid** | `https://raw.githubusercontent.com/plaid/plaid-openapi/master/2020-09-14.yml` | YAML 3.0.0 | большая | apiKey в теле/заголовках | `POST /transfer/create`, `POST /transfer/get` (**статус через POST с id в теле**) — ожидаем WARN `no_status_endpoint` и запись в «Ограничения» |

## 1a. Вторая волна (6.09.2026, ссылки проверены, HTTP 200)

| Имя | Провайдер / API | URL (raw) | Что ожидаем |
|---|---|---|---|
| velo | **Velo Payments** (payouts) | `https://api.apis.guru/v2/specs/velopayments.com/2.34.63/openapi.json` | create `POST /v3/payouts`, status, cancel; 201 без тела → фикстура `{}` |
| increase | **Increase** (account transfers) | `https://api.apis.guru/v2/specs/increase.com/0.0.1/openapi.json` | create/status/cancel по `/account_transfers`; минимум 1 цент → без `MIN_AMOUNT` |
| mollie | **Mollie** (OpenAPI 3.1, 1.9 МБ) | `https://raw.githubusercontent.com/mollie/openapi/main/specs.yaml` | create `POST /v2/payouts`, status `GET /v2/payouts/{id}` — tie-break по ресурсу create |
| dwolla | **Dwolla** (OpenAPI 3.1) | `https://raw.githubusercontent.com/Dwolla/dwolla-openapi/main/openapi.yml` | create `POST /transfers`, status, cancel; 201 без тела |
| wise_transfer | **Wise** Transfer API (OpenAPI 3.2, профиль api-evangelist) | `https://raw.githubusercontent.com/api-evangelist/wise/main/openapi/wise-transfer-api-openapi.yml` | create/status/cancel, webhook из `webhooks`; callback без примера → pending в spec |
| openbanking_pis | **Open Banking UK** Payment Initiation | `https://api.apis.guru/v2/specs/openbanking.org.uk/payment-initiation-openapi/3.1.7/openapi.json` | create — consent (WARN role_conflict → override); поле `Currency` → переменная `currency` |
| nowpayments | **NOWPayments** (crypto) | `https://api.apis.guru/v2/specs/nowpayments.io/1.0.0/openapi.json` | в спеке нет `POST /payout` → `no_create_endpoint` |
| klarna | **Klarna Payments** (pay-in) | `https://api.apis.guru/v2/specs/klarna.com/payments/1.0.0/openapi.json` | `no_create_endpoint` |
| payone_link | **PAYONE Link** (платёжные ссылки, pay-in) | `https://api.apis.guru/v2/specs/pay1.de/link/v1/openapi.json` | `link/links` — negative word → `no_create_endpoint` |
| vtex_gateway | **VTEX** Payments Gateway (pay-in) | `https://api.apis.guru/v2/specs/vtex.local/Payments-Gateway-API/1.0/openapi.json` | create с WARN low_confidence (слов выплаты нет); integer в мажорных единицах → `.to_i` |
| adyen_balance | **Adyen Balance Platform** (конфигурация) | `https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/BalancePlatformService-v2.json` | `calculate` — negative word; реквизиты по умолчанию режутся по `maxLength` |
| adyen_checkout | **Adyen Checkout** (pay-in, 390 WARN) | `https://raw.githubusercontent.com/Adyen/adyen-openapi/main/json/CheckoutService-v71.json` | ключи с точкой (`cupsecureplus.smscode`) квотируются; `links`/`methods` — negative |
| govuk_pay | **GOV.UK Pay** (Swagger 2.0) | `https://api.apis.guru/v2/specs/payments.service.gov.uk/payments/1.0.3/swagger.json` | exit 1: «Swagger 2.0 is not supported; convert to OpenAPI 3» |

Все 13 регистрируются в `Rakefile` (`REAL_SPECS`) и `spec/real_specs_spec.rb`; отчёты — `examples/real/reports/*.txt`.
`generate` на них: 8 сервисов с зелёным сгенерированным spec (Velo, Increase, Mollie, Dwolla, Wise, Open Banking,
VTEX, Adyen Balance/Checkout — с WARN), 4 честных `no_create_endpoint` (exit 2), 1 Swagger 2.0 (exit 1).

Лицензии второй волны: Velo — Apache-2.0; Open Banking — Open Licence; Dwolla — MIT; Adyen — MIT; Mollie — CC-BY-NC-SA-4.0
(только скачиваем для тестов, не распространяем); Wise (профиль api-evangelist), Increase, NOWPayments, Klarna, PAYONE,
VTEX, GOV.UK — через apis.guru, лицензия провайдера. Спеки в git не попадают.

Ранее «не найдено»: Dwolla, Wise и Mollie теперь в корпусе (см. выше).

Лицензии: Stripe — MIT; Adyen — MIT; PayPal — Apache-2.0; Square — Apache-2.0; Paystack — MIT; Plaid — MIT.
Мы только читаем файлы в тестах, ничего не распространяем.

## 2. Что ожидаем от forge (гипотезы → проверяет T18, расхождения → карточки или «Ограничения»)

| Спека | Команда | Ожидание |
|---|---|---|
| Adyen Payout | `analyze --spec examples/real/adyen_payout.json` | create = `POST /payout` с **confidence ≈ 0.75 → WARN low_confidence** (нет create-слова); WARN `no_status_endpoint`, WARN `no_webhook`; auth apiKey X-API-Key; amount `amount.value` minor 0.9; exit 0. С `overrides: endpoints.post-payout: create` → без WARN роли |
| Adyen Transfers | `analyze --spec examples/real/adyen_transfers.json` | create `POST /transfers` 0.85+; status `GET /transfers/{id}` 0.9; cancel `POST /transfers/cancel` (без path param, есть body) ≥ 0.5 + WARN; **много unmapped_status** (ожидаем > 50 WARN — это честно; отчёт сворачивает список: «и ещё N»); WARN `api_key_in_query_ignored`; exit 0 |
| PayPal Payouts | `analyze --spec examples/real/paypal_payouts.json` | UNSUPPORTED `oauth2` (bearer с TODO); create `POST /v1/payments/payouts` 0.95; WARN `array_field_unsupported` (`items[]`); статусы `batch_status` enum: PENDING/PROCESSING → in_progress, SUCCESS → approved, DENIED/CANCELED → rejected; exit 0 |
| Paystack | `analyze --spec examples/real/paystack.yaml --include-paths '/transfer*' --include-paths '/balance'` | media type → json; create `POST /transfer` 0.85; status `GET /transfer/{code}` 0.9 (или verify — конфликт → WARN); balance; amount minor по маркеру `kobo`; `$ref` с `~1` резолвится; exit 0 |
| Stripe | `analyze --spec examples/real/stripe.json --include-paths '/v1/payouts*'` | загрузка ≤ 10 с; create/status/cancel 0.9+; WARN `media_type_form` (генерируем `form:`); WARN `status_from_description`; WARN `no_webhook`; exit 0. Без `--include-paths` — WARN `role_conflict` для transfers/treasury и подсказка про `--include-paths` |
| Square | `generate --spec examples/real/square.json --include-paths '/v2/payouts*'` | `GenerationError: no create endpoint` exit 2 с подсказкой; `analyze` — exit 0 с WARN `no_create_endpoint` |
| Plaid | `analyze --spec examples/real/plaid.yml --include-paths '/transfer/*'` | create `POST /transfer/create`; status не найден (нет path param) → WARN `no_status_endpoint` + подсказка; exit 0 |

Числа confidence здесь — ожидания по формулам `docs/RULES.md`; T18 фиксирует фактические в снапшотах.

## 3. Инструменты (Ruby, `Rakefile`)

```
rake real:fetch          # Net::HTTP → examples/real/<name>.<ext> (пропускает уже скачанные)
rake real:analyze        # bin/forge analyze для каждой → examples/real/reports/<name>.txt (+ .json), сводная таблица
rake real               # REAL=1 bundle exec rspec spec/real_specs_spec.rb
```

`spec/real_specs_spec.rb` — по одному `describe` на спеку; `skip 'run rake real:fetch'` если файла нет;
проверяет код выхода, роли/auth из таблицы ожиданий и совпадение отчёта со снапшотом
(`REAL_UPDATE=1` обновляет).

## 4. Как это подаём

- README → раздел «Проверено на реальных спецификациях»: таблица провайдер → что распознано → что
  потребовало overrides → ссылка на отчёт. **WARN — это честность инструмента, а не сбой.**
- Питч: один слайд «7 реальных API, 0 падений, N решений автоматически, M — с подсказкой».
- CI job `real-specs`: `workflow_dispatch` + расписание, `continue-on-error: true`, отчёты — артефакт.
  В обязательный CI не включаем (сеть, размер).

## 5. Известные ограничения, которые вскроют реальные спеки (пишем в README честно)

1. Статус-запрос через `POST` с id в теле (Plaid) — не генерируется (`status_request_field` в roadmap).
2. Batch-выплаты (PayPal `items[]`) — массивы полей не мапятся автоматически.
3. Form-urlencoded (Stripe) — поддержан в `HttpClient` (`form:`), но вложенные объекты Stripe-стиля
   (`destination[account]`) кодируются плоско — WARN.
4. Огромные enum статусов (Adyen Transfers) — мапятся только общеупотребительные; остальное — overrides.
5. OAuth2 — токен не получаем; генерируем bearer с TODO.
