# Демо CP3 — сценарий на 7 минут

Запуск: `bin/demo` (NovaPay) — 5 шагов с паузами; `bin/demo examples/specs/cardpay.yaml --fast` — второй провайдер без пауз.
Бэкап: `tmp/demo/*` после первого прогона, `examples/real/reports/*.txt` для реальных спек.

| Мин | Шаг | Что говорим | Что на экране |
|---|---|---|---|
| 0–1 | Постановка | Вход — OpenAPI, выход — сервис по контракту + доказательства. Без LLM: правила, словари, детерминизм. | README «Как это работает» (схема шести стадий) |
| 1–2 | `analyze` | Роли с confidence, auth, статусы, ошибки, подпись webhook, единицы суммы. Три WARN — это допущения из description, не догадки молча. | `bin/forge analyze --spec examples/specs/novapay.yaml` |
| 2–3 | `generate` | Шесть файлов; сервис проходит `ruby -c` и собственный RSpec (13 примеров) прямо в генерации. | вывод generate, `novapay_service.rb` (check_conditions, build_recipient с вариантами sbp/card) |
| 3–4 | Доказательство | Сгенерированный spec на WebMock и фикстурах из примеров спеки; тело запроса сверяется с примером провайдера. | `bundle exec rspec …_service_spec.rb` |
| 4–5 | e2e | Мок из той же спеки: 401/422/409-идемпотентность; `_simulate` шлёт подписанный webhook → `operation approved ✓`. | `bin/e2e examples/specs/novapay.yaml` |
| 5–6 | Универсальность | CardPay (bearer, строка в рублях, `data`-обёртка, callbacks, sha512/base64): 5 WARN → overrides → 0 WARN, `--strict` exit 0. SwiftPay 3.1: oneOf, allOf, DELETE-cancel, UNSUPPORTED без падения. | `bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --strict` |
| 6–7 | Реальные API | 7 спек (Stripe 8 МБ за 0.1 с, Adyen, PayPal, Paystack, Square, Plaid): exit 0, отчёты в репозитории; honest WARN. Критерий → где смотреть. | `examples/real/reports/SUMMARY.md`, README таблица |

Вопросы, к которым готовы: «почему не LLM» (объяснимость + детерминизм, требование ТЗ), «что при плохой спеке»
(UNSUPPORTED + overrides, падаем только без create), «как добавить правило» (`rules/*.yml`, `docs/RULES.md` § 10).
