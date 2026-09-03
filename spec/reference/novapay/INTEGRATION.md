# NovaPay Integration Guide

## Авторизация

- Тип: API Key
- Header: `X-API-Key: <credentials.api_key>`
- Хранение: `providers.credentials` (encrypted)

## Методы

| Метод | Endpoint | Назначение | Idempotency |
|-------|----------|------------|-------------|
| create_payout | POST /payouts | Создание выплаты | Idempotency-Key header |
| get_status | GET /payouts/{id} | Статус | - |
| cancel | POST /payouts/{id}/cancel | Отмена | - |
| webhook | POST /webhooks/payout | Callback | X-NovaPay-Signature |

## Маппинг статусов

| Provider | Space Payments |
|----------|----------------|
| pending | in_progress |
| processing | in_progress |
| completed | approved |
| failed | rejected |
| cancelled | rejected |

## Обработка ошибок

| HTTP | Provider code | Действие |
|------|---------------|----------|
| 400 | validation_error | reject |
| 401 | unauthorized | alert ops, block provider |
| 402 | insufficient_balance | retry later |
| 429 | rate_limit_exceeded | retry with backoff |
| 500 | internal_error | retry, alert ops |

## ProviderGateway config

{ "external_method": "sbp_payout", "gateway": "RUB_SBP_WITHDRAW" }

## Webhook signature

HMAC-SHA256(body, callback_secret) → hex → X-NovaPay-Signature
