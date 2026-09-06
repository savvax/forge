# Условие задачи (сжато)

Полный текст — `описание.docx` в материалах хакатона. Здесь — то, что нужно держать в голове.

**Проблема.** Space Payments регулярно подключает платёжных провайдеров. Каждая интеграция — Ruby-сервис
с единым контрактом (`Provider::BaseService`: `check_conditions`, `create_request`, `process_callback`,
`fetch_status`). Разработчик читает документацию и пишет сервис с нуля: 2–5 дней.

**Задача.** Инструмент, который принимает открытую документацию API провайдера (OpenAPI — единственный
формат по QA 1) и генерирует интеграцию.

**Вход.** `provider_api.yaml` — OpenAPI 3.0.3 «NovaPay Payout API»: `POST /payouts`, `GET /payouts/{payout_id}`,
`POST /payouts/{payout_id}/cancel`, `POST /webhooks/payout` (HMAC-SHA256 в `X-NovaPay-Signature`), `GET /balance`;
auth `X-API-Key`; `Idempotency-Key`; сумма в копейках, минимум 1000 RUB; статусы pending/processing/completed/failed/cancelled.
Копия — `examples/specs/novapay.yaml`.

**Выход.**
1. `novapay_service.rb` по контракту (эталон — `spec/reference/novapay/novapay_service.rb`).
2. `INTEGRATION.md`: авторизация, методы, маппинг статусов, ошибки, ProviderGateway config, подпись webhook
   (эталон — `spec/reference/novapay/INTEGRATION.md`).
3. `fixtures.json`: request/response_201/response_422, fetch_status, callback, callback_failed с `expected_operation_status`
   (эталон — `spec/reference/novapay/fixtures.json`).
4. CLI: `./integrate --spec provider_api.yaml --provider novapay --lang ruby` с прогресс-выводом
   («Parsing spec… Found 5 endpoints… Auth… Webhook signature… Generating… Output:»).

**Только выплаты.** Депозиты не нужны. Доп. эндпоинты (balance, cancel) — «найдено, вне контракта».

**Ограничения.** Open-source; большинство кода на Ruby; нейросети внутри проекта запрещены.

**Оценка.** Рубрики жюри → где смотреть в проекте: раздел «Критерий → где смотреть» в README.
