# Реальные спеки — сводка `rake real:analyze`

| Спека | Флаги | Код | Итог |
|---|---|---|---|
| stripe | --include-paths /v1/payouts* | exit 0 | Done: 11 warnings, 1 unsupported. Exit 0. |
| adyen_payout |  | exit 0 | Done: 40 warnings, 1 unsupported. Exit 0. |
| adyen_transfers |  | exit 0 | Done: 104 warnings, 2 unsupported. Exit 0. |
| paypal_payouts |  | exit 0 | Done: 10 warnings, 0 unsupported. Exit 0. |
| paystack | --include-paths /transfer* --include-paths /balance | exit 0 | Done: 8 warnings, 0 unsupported. Exit 0. |
| square | --include-paths /v2/payouts* | exit 0 | Done: 7 warnings, 9 unsupported. Exit 0. |
| plaid | --include-paths /transfer/* | exit 0 | Done: 57 warnings, 0 unsupported. Exit 0. |
| velo |  | exit 0 | Done: 28 warnings, 0 unsupported. Exit 0. |
| increase |  | exit 0 | Done: 37 warnings, 0 unsupported. Exit 0. |
| mollie |  | exit 0 | Done: 35 warnings, 1 unsupported. Exit 0. |
| dwolla |  | exit 0 | Done: 22 warnings, 0 unsupported. Exit 0. |
| wise_transfer |  | exit 0 | Done: 22 warnings, 1 unsupported. Exit 0. |
| openbanking_pis |  | exit 0 | Done: 78 warnings, 0 unsupported. Exit 0. |
| nowpayments |  | exit 0 | Done: 9 warnings, 0 unsupported. Exit 0. |
| klarna |  | exit 0 | Done: 7 warnings, 0 unsupported. Exit 0. |
| payone_link |  | exit 0 | Done: 7 warnings, 0 unsupported. Exit 0. |
| vtex_gateway |  | exit 0 | Done: 16 warnings, 0 unsupported. Exit 0. |
| adyen_balance |  | exit 0 | Done: 51 warnings, 0 unsupported. Exit 0. |
| adyen_checkout |  | exit 0 | Done: 390 warnings, 1 unsupported. Exit 0. |
| govuk_pay |  | exit 1 | error: Swagger 2.0 is not supported; convert to OpenAPI 3 at #/swagger in examples/real/govuk_pay.json |
