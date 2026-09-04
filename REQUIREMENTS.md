# Space Payments Hackathon — Задача 1. Полное задание и технические требования

Документ-эталон для приёмки проекта `forge` (генератор интеграций с платёжными провайдерами).
Собран 4 сентября 2026 из: описания кейса (`описание.docx`), примера спеки (`provider_api.yaml`),
ответов организаторов на QA 1 (3–4.09.2026, устно и письменно), внутренних документов проекта
(`CLAUDE.md`, `ARCHITECTURE.md`, `AGENT_TASKS.md`, `hackathon-plan.md`).

Каждое требование имеет идентификатор. Обозначения источника:
- **[ТЗ]** — требование организаторов из описания кейса. Нарушение — потеря баллов или дисквалификация.
- **[QA]** — уточнение организаторов на QA-сессии. Имеет приоритет над догадками.
- **[FORGE]** — внутреннее проектное решение команды. Проверяется как часть DoD, но не диктуется организаторами.

Уровни обязательности: **MUST** — без этого проект не принимается; **SHOULD** — ожидается, влияет на баллы;
**MAY** — резерв.

---

## 1. Постановка задачи [ТЗ]

### 1.1 Проблема

Space Payments регулярно подключает новых платёжных провайдеров. Каждая интеграция — Ruby-сервис с единым
контрактом. Сейчас разработчик вручную читает документацию провайдера и пишет сервис с нуля: 2–5 дней на
интеграцию.

**Задача:** создать инструмент, который принимает открытую документацию API провайдера (OpenAPI) и
генерирует интеграцию провайдера.

### 1.2 Контракт `Provider::BaseService`

```ruby
class Provider::ExampleService < Provider::BaseService
  def check_conditions(operation, request_method)   # предпроверки
  def create_request(operation, ...)                # создание выплаты/депозита
  def process_callback(payload)                     # обработка webhook
  def fetch_status(operation)                       # статус-запрос
end
```

- Реальный класс `Provider::BaseService` существует в кодовой базе Space Payments, но **не выдаётся**.
  Полный production-класс и harness не обязательны; собственная заглушка контракта допустима [QA].
- `request_method` в `create_request(operation, request_method)` — **не HTTP-метод**, а логический тип
  действия: payment-method шлюза (`sbp` / `card` / `bank_account` …) либо служебное `status` / `check` [QA].
  HTTP-verb всегда берётся из спеки.
- Модель `operation` не уточнялась; берётся из примера ТЗ: `operation.id`, `operation.amount` (в мажорных
  единицах), `operation.payout_requisite` (Hash, например `dig('sbp', 'phone')`),
  `operation.provider_operation_id` [QA].

### 1.3 Входные данные

| Файл | Описание |
|---|---|
| `provider_api.yaml` | OpenAPI 3.0.3 спецификация NovaPay Payout API: куда отправлять запросы, какие данные передавать, какие ответы ожидать |

- Вход — **только OpenAPI** (YAML или JSON). PDF/HTML-документация не подаётся [QA].
- Область — **только выплаты (payout)**. Депозиты / pay-in не требуются [QA].

Содержимое эталонной спеки NovaPay (ключевые факты, которые должны быть распознаны):

| Элемент | Значение |
|---|---|
| Серверы | `https://api.sandbox.novapay.example/v1` (Sandbox), `https://api.novapay.example/v1` (Production) |
| Auth | `ApiKeyAuth`: `type: apiKey`, `in: header`, `name: X-API-Key` |
| `POST /payouts` (`createPayout`) | Создание выплаты. Header `Idempotency-Key` (uuid, optional). Body `CreatePayoutRequest`. Ответы 201, 400, 401, 402, 409, 422, 429, 500 |
| `GET /payouts/{payout_id}` (`getPayoutStatus`) | Статус. Ответы 200, 401, 404 |
| `POST /payouts/{payout_id}/cancel` (`cancelPayout`) | Отмена только в pending/processing. Ответы 200, 409 |
| `POST /webhooks/payout` (`payoutWebhook`) | `security: []`; header `X-NovaPay-Signature` (required, HMAC-SHA256 тела). Body `WebhookPayload`. Ответ 200 `{received: true}` |
| `GET /balance` (`getBalance`) | Баланс в копейках: `balance`, `currency`, `hold` |
| `CreatePayoutRequest` | required: `amount` (integer, копейки, minimum 100000), `currency` (enum [RUB]), `external_id` (maxLength 64), `recipient` |
| `Recipient` | required: `type` (enum [sbp, card]), `phone` (pattern `^7\d{10}$`); optional: `bank_code` (БИК, обязателен для type=sbp — только в description), `bank_name`, `card_number` (обязателен для type=card — только в description) |
| `PayoutResponse.status` | enum: pending, processing, completed, failed, cancelled |
| `PayoutError.code` | enum: validation_error, insufficient_balance, recipient_not_found, bank_unavailable, amount_limit_exceeded, rate_limit_exceeded, internal_error |
| `WebhookPayload` | required: `event` (enum payout.completed / payout.failed / payout.processing / payout.cancelled), `payout_id`, `status`; optional `external_id`, `completed_at`, `error` |
| Ответ 429 | header `Retry-After` (секунды) |
| Примеры | request `sbp_payout`; response 201; 402/422/401/429 примеры ошибок; webhook `completed` и `failed` |

### 1.4 Ожидаемый результат работы решения

Система получает `provider_api.yaml` на входе и отдаёт **несколько файлов** на выходе.

#### 1.4.1 Сгенерированный сервис по контракту `Provider::BaseService`

Эталон из ТЗ (`app/services/provider/novapay_service.rb`):

```ruby
class Provider
  class NovapayService < BaseService
    BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')

    def create_request(operation, request_method = 'create')
      payload = build_payout_payload(operation)
      response = client.post("#{BASE_URL}/payouts", json: payload, headers: auth_headers)
      parse_create_response(operation, response)
    rescue Provider::RateLimitError
      failure(:too_many_requests, 'provider.rate_limit')
    rescue Provider::UnauthorizedError
      failure(:unauthorized, 'provider.invalid_credentials')
    end

    def fetch_status(operation)
      response = client.get("#{BASE_URL}/payouts/#{operation.provider_operation_id}")
      map_status(response.body['status'])
    end

    def process_callback(payload)
      verify_signature!(payload) # HMAC-SHA256 из X-NovaPay-Signature
      case payload['event']
      when 'payout.completed' then approve_operation(payload['payout_id'])
      when 'payout.failed'    then reject_operation(payload['payout_id'], payload.dig('error', 'code'))
      else failure(:unprocessable_entity, 'unknown_event')
      end
    end

    def check_conditions(operation, request_method)
      base_result = super
      return base_result if base_result.failed?
      return failure(:unprocessable_entity, 'amount_too_low') if operation.amount < 1000
      success
    end

    private

    def build_payout_payload(operation)
      {
        amount: (operation.amount * 100).to_i,
        currency: 'RUB',
        external_id: operation.id,
        recipient: {
          type: 'sbp',
          phone: operation.payout_requisite.dig('sbp', 'phone'),
          bank_code: operation.payout_requisite.dig('sbp', 'bank_code'),
          bank_name: operation.payout_requisite.dig('sbp', 'bank_name')
        }
      }
    end

    STATUS_MAP = {
      'pending'    => 'in_progress',
      'processing' => 'in_progress',
      'completed'  => 'approved',
      'failed'     => 'rejected',
      'cancelled'  => 'rejected'
    }.freeze

    ERROR_MAP = {
      400 => 'validation_error',
      401 => 'invalid_credentials',
      402 => 'insufficient_balance',
      422 => 'validation_error',
      429 => 'rate_limit',
      500 => 'internal_error'
    }.freeze
  end
end
```

Обязательные элементы сгенерированного сервиса (проверяются по эталону):

| ID | Требование |
|---|---|
| S-01 | Класс `Provider::<Name>Service < BaseService` |
| S-02 | Константа `BASE_URL` из `ENV.fetch('<PREFIX>_BASE_URL', <sandbox url из спеки>)` |
| S-03 | `create_request(operation, request_method)` — строит payload, отправляет запрос методом/путём из спеки, парсит ответ |
| S-04 | `rescue` типизированных ошибок клиента (`RateLimitError` → `failure(:too_many_requests, …)`, `UnauthorizedError` → `failure(:unauthorized, …)`) |
| S-05 | `fetch_status(operation)` — GET статус-эндпоинт с `operation.provider_operation_id`, маппинг статуса |
| S-06 | `process_callback(payload)` — `verify_signature!`, ветвление по событию: completed → `approve_operation`, failed → `reject_operation(id, error_code)`, иное → `failure(:unprocessable_entity, 'unknown_event')` |
| S-07 | `check_conditions(operation, request_method)` — `super`, затем валидации из схемы (минимальная сумма → `amount_too_low`) |
| S-08 | `build_payout_payload` — конверсия суммы в единицы провайдера (`(operation.amount * 100).to_i` для копеек), валюта, `external_id: operation.id`, реквизиты из `operation.payout_requisite` |
| S-09 | `STATUS_MAP` (frozen) — статусы провайдера → `in_progress` / `approved` / `rejected` |
| S-10 | `ERROR_MAP` (frozen) — HTTP-код → внутренний код |
| S-11 | Auth-заголовки из спеки (`X-API-Key` из credentials) |
| S-12 | Секреты (API key, HMAC secret) — через `credentials` с плейсхолдером для ручного заполнения [QA] |

#### 1.4.2 Документация интеграции `INTEGRATION.md`

Эталон из ТЗ — обязательные разделы и таблицы:

```markdown
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
```

| ID | Требование |
|---|---|
| D-01 | Раздел «Авторизация»: тип, header, хранение credentials |
| D-02 | Таблица «Методы»: метод, endpoint, назначение, idempotency/подпись |
| D-03 | Таблица «Маппинг статусов» |
| D-04 | Таблица «Обработка ошибок»: HTTP, код провайдера, действие |
| D-05 | `ProviderGateway config` (`external_method`, `gateway`) |
| D-06 | Раздел «Webhook signature»: алгоритм, что подписывается, кодировка, заголовок |
| D-07 | Раздел «Допущения» (Assumptions): все решения с confidence < 0.8, источник (structure / description / эвристика / override), как переопределить [QA — эксперты просили явно] |

#### 1.4.3 Тестовые фикстуры `fixtures.json`

Эталон из ТЗ:

```json
{
  "create_request": {
    "request": {
      "amount": 1500000, "currency": "RUB", "external_id": "op_abc123",
      "recipient": { "type": "sbp", "phone": "79001234567", "bank_code": "044525225" }
    },
    "response_201": { "id": "np_7f3a9b2c", "status": "pending" },
    "response_422": { "error": { "code": "validation_error", "message": "Amount must be at least 100000 kopecks" } }
  },
  "fetch_status": { "response_200": { "id": "np_7f3a9b2c", "status": "completed" } },
  "callback": {
    "payload": { "event": "payout.completed", "payout_id": "np_7f3a9b2c", "status": "completed" },
    "expected_operation_status": "approved"
  },
  "callback_failed": {
    "payload": { "event": "payout.failed", "payout_id": "np_7f3a9b2c", "status": "failed", "error": { "code": "recipient_not_found" } },
    "expected_operation_status": "rejected"
  }
}
```

| ID | Требование |
|---|---|
| F-01 | Ключи `create_request` (`request`, `response_201`, `response_422`), `fetch_status`, `callback`, `callback_failed` присутствуют |
| F-02 | Значения ТЗ ⊆ сгенерированных (можно дополнять, нельзя терять) |
| F-03 | `expected_operation_status` для каждого callback |
| F-04 | Примеры берутся из `examples`/`example` спеки; при отсутствии — детерминированный синтез по схеме |
| F-05 | Исполняемые тесты не требуются, но не запрещены [QA] |

#### 1.4.4 CLI

Эталонный вывод из ТЗ:

```
$ ./integrate --spec provider_api.yaml --provider novapay --lang ruby
Parsing spec...
Found 5 endpoints: POST /payouts, GET /payouts/{id}, POST /payouts/{id}/cancel,
                  POST /webhooks/payout, GET /balance
Auth: ApiKeyAuth (header: X-API-Key)
Webhook signature: X-NovaPay-Signature (HMAC-SHA256)
Generating service...
Generating integration guide...
Generating test fixtures...
Output:
  ./output/novapay_service.rb
  ./output/INTEGRATION.md
  ./output/fixtures.json
```

| ID | Требование |
|---|---|
| C-01 | Команда `./bin/integrate --spec FILE --provider NAME --lang ruby` работает и генерирует все файлы за один запуск |
| C-02 | Прогресс-вывод повторяет структуру ТЗ: Parsing → Found N endpoints → Auth → Webhook signature → Generating … → Output |
| C-03 | Веб-интерфейс не требуется — CLI достаточно для максимума баллов [QA] |

### 1.5 Ограничения (нарушение = дисквалификация) [ТЗ]

| ID | Требование |
|---|---|
| X-01 | **Нельзя** использовать проприетарные технологии и решения с закрытым исходным кодом. Все зависимости — open-source (MIT/Apache/BSD) |
| X-02 | **Большинство кода в репозитории — на Ruby.** Числового порога нет; ядро и логика — чистый Ruby; Ruby-обёртка над логикой на другом языке = нарушение. HTML/CSS/Dockerfile/Makefile/YAML/CI — допустимы [QA] |
| X-03 | **Запрещено использование нейросетей внутри проекта.** Инструмент не вызывает LLM/ML ни в каком виде; вся классификация — правила, словари, регулярные выражения, подсчёт очков. AI-ассистированная разработка (написание кода агентами) разрешена [QA] |
| X-04 | Коммит после стоп-кода (вс 6.09 23:00 MSK = пн 7.09 01:00 ALA) — автоматическая дисквалификация; проверяется история коммитов. Внутренний дедлайн последнего пуша — **00:00 ALA (22:00 MSK) вс 6.09** [QA] |
| X-05 | Версия Ruby — как можно новее: 3.x (проект организаторов на Ruby 3) [QA] |

### 1.6 Уточнения организаторов [QA]

| ID | Уточнение |
|---|---|
| Q-01 | Скрытых/других спек на проверке не будет, но решение должно работать с любой OpenAPI-спекой; по коду будут смотреть, что парсятся общие конструкции, а не конкретный файл. Совет: проверить на открытых спеках платёжных провайдеров |
| Q-02 | Дополнительные эндпоинты (balance, cancel, refund) в контракт не входят: перечислять в отчёте как «найдено, вне контракта»; в сервис — только как необязательные хелперы. Структуру класса из ТЗ сохранять |
| Q-03 | Output не обязан быть production-ready: приватные ключи/секреты — плейсхолдеры для ручного заполнения; URL — из спеки; amount/реквизиты — из `operation` |
| Q-04 | Неоднозначное из структуры спеки — автоматически; лежащее текстом в `description` (единицы суммы, условная обязательность, детали подписи) — WARN/TODO + опциональный **общий** `overrides.yml`. Это не считается привязкой к провайдеру, пока overrides — механизм (`amount_unit`, `required_if`, `signature_encoding`), а не хардкод в ядре. Эвристики — best-effort, **критичное молча не угадывать** |
| Q-05 | Неподдерживаемый критичный элемент → явная ошибка с подсказкой (как в production-коде), а не тихая заглушка. Некритичный → WARN |
| Q-06 | Канон маппинга статусов, если в спеке нет таблицы: `pending`/`processing` → `in_progress`, `completed` → `approved`, `failed`/`cancelled` → `rejected`. Использовать наборы популярных названий (NEW, SUCCESS, DECLINED, ON_HOLD, captured …). Допущения — в `INTEGRATION.md` |
| Q-07 | Канон NovaPay для эталона: сумма в копейках (×100); `bank_code` обязателен при `type=sbp`; подпись webhook `HMAC-SHA256(raw body, secret)` → hex |
| Q-08 | Реально стучаться к провайдеру не нужно; абстрактный `client` бьёт по URL с payload |
| Q-09 | Документация = оба артефакта: сгенерированный `INTEGRATION.md` и документация проекта (паттерны, почему такие решения, схема пайплайна, запуск). Язык — любой, русский допустим. При отсутствии документации — 0 по критерию, остальные независимы |
| Q-10 | Проверяют прежде всего код в репозитории; жюри могут развернуть — нужна инструкция «зашёл, запустил, понял». Docker не обязателен, стек не ограничен |
| Q-11 | Минимум по надёжности: код не падает на первой ошибке. Retry/circuit breaker/очереди — вне критериев, но могут добавить баллов |
| Q-12 | «Дополнительные идеи» (6 баллов) — то, что выделяет команду: killer-фичи, исследование, глубина. Обязательно явно подсветить в README и на питче |
| Q-13 | Баллы ставятся на финальное решение; чек-поинты — фидбэк. CP3 (вс 6.09, 13:00 MSK / 15:00 ALA) обязателен хотя бы для одного члена команды |
| Q-14 | На стоп-код отправляется одна ссылка на репозиторий (вероятно, публичный) |

---

## 2. Критерии оценки [ТЗ]

Итог = баллы технического жюри (100) + отраслевого жюри (20). Эксперты (100, по трём чек-поинтам) отбирают топ-5
на защиту; в итоговую сумму их баллы не входят.

### 2.1 Эксперты (чек-поинты, макс. 100)

| Критерий | Макс | Разбалловка |
|---|---|---|
| 1. Корректность разбора API-спецификации | 20 | 8 — основные методы и параметры запросов/ответов; 7 — авторизация, статусы операций, ошибки; 5 — webhook и другие условия взаимодействия |
| 2. Генерация интеграционного сервиса | 25 | 10 — сервис формирует и отправляет запросы; 8 — обрабатывает ответы, статусы, ошибки; 7 — входящие уведомления и настройка параметров подключения |
| 3. Корректность преобразования данных | 15 | 8 — поля запросов/ответов и статусы; 7 — форматы данных, обязательные/необязательные поля |
| 4. Универсальность решения | 15 | 7 — работает со спеками с разным набором методов/полей; 5 — логика не привязана к одному провайдеру; 3 — добавление новых правил и обработка неподдерживаемых элементов |
| 5. Понятность использования и демонстрации | 15 | 6 — запуск и результат через понятный последовательный процесс; 5 — информация по настройке, авторизации, использованию; 4 — результат и ошибки в понятном виде |
| 6. Качество технической реализации | 10 | 6 — понятная структура, разделение компонентов; 4 — обработка ошибок при разборе спеки и генерации |

### 2.2 Техническое жюри (защита, макс. 100)

| Критерий | Макс | Разбалловка |
|---|---|---|
| 1. Разбор API-спецификации | 20 | 5 — методы API; 5 — параметры запросов/ответов; 4 — авторизация; 3 — статусы и ошибки; 3 — webhook и доп. условия |
| 2. Генерация интеграционного сервиса | 25 | 5 — соответствие контракту `Provider::BaseService`; 5 — формирование и отправка запросов; 4 — получение и обработка статуса; 4 — обработка ответов и ошибок; 4 — входящие уведомления; 3 — конфигурация адресов и параметров |
| 3. Корректность преобразования данных | 15 | 5 — статусы; 4 — поля запросов/ответов; 3 — форматы и единицы; 3 — обязательные/необязательные поля |
| 4. Универсальность и адаптируемость | 10 | 5 — разные наборы методов и полей; 3 — логика генерации отделена от провайдера; 1 — расширение шаблонов и правил; 1 — сообщения о неподдерживаемых/неоднозначных элементах |
| 5. Документация и тестовые материалы | 13 | 5 — настройка и авторизация; 4 — методы, статусы, ошибки; 4 — примеры запросов/ответов/уведомлений в `fixtures.json` |
| 6. Удобство использования и демонстрация | 10 | 4 — понятный запуск; 3 — результат за один процесс; 3 — понятные сообщения о результате и ошибках |
| 7. Качество реализации | 10 | 4 — архитектура и читаемый код; 3 — обработка ошибок при разборе и генерации; 3 — инструкция по запуску и настройке |

### 2.3 Отраслевое жюри (макс. 20)

| Критерий | Баллы |
|---|---|
| Реализация дополнительных идей | 6 |
| Выступление команды (логичный, понятный, интересный рассказ) | 6 |
| Полнота проработки решения | 8 |

---

## 3. Процесс и сроки [ТЗ]

| Дата (MSK; ALA = +2 ч) | Событие |
|---|---|
| Чт 3.09 15:00 | Задачи открыты; 19:00 открытие; 19:30–20:30 QA |
| Пт 4.09, Сб 5.09, Вс 6.09, 13:00–16:00 | Чек-поинты с экспертами (10 мин, слот назначает модератор) |
| Вс 6.09 23:00 | **Стоп-код.** Коммит после — дисквалификация |
| Пн 7.09 20:00 | Топ-5 по каждой задаче |
| Вт 8.09 17:00–19:00 | Питчи; 19:00–20:00 обсуждение жюри; 20:00 награждение |

---

## 4. Технические требования к решению `forge` [FORGE]

### 4.1 Стек и зависимости

| ID | Требование | Уровень |
|---|---|---|
| T-01 | Ruby 3.3+ (Docker `ruby:3.3-slim`); `# frozen_string_literal: true` в каждом файле | MUST |
| T-02 | Runtime-гемы: `thor` (CLI); stdlib `erb`, `psych`, `json`, `openssl`, `securerandom` | MUST |
| T-03 | Сгенерированный код / заглушка: `faraday` | MUST |
| T-04 | Dev/test: `rspec`, `webmock`, `rubocop`, `rubocop-rspec` | MUST |
| T-05 | Мок-сервер: `sinatra`, `rackup`, `puma` | SHOULD |
| T-06 | Опционально после обсуждения: `json_schemer` | MAY |
| T-07 | Новый гем — только после явного решения человека; все гемы — open-source лицензии | MUST |
| T-08 | Никаких сетевых вызовов во время генерации; одинаковый вход → байт-в-байт одинаковый выход (детерминизм: без времени, случайных значений, путей машины в выходе) | MUST |

### 4.2 Архитектура

Шесть стадий, одна направленная цепочка данных. Стадия не знает о соседях дальше чем на шаг:
парсер не знает о Ruby-коде, шаблоны не знают об OpenAPI.

```
                 rules/*.yml                overrides.yml
                     │                           │
provider_api.yaml ─▶ Load ─▶ IR ─▶ Analyze ─▶ Plan ─▶ Render ─▶ Verify ─▶ Report
                      │             │           │        │         │
                  SpecError     Findings  IntegrationPlan  files  ruby -c / rspec
```

| ID | Требование | Уровень |
|---|---|---|
| A-01 | **Load** (`lib/forge/loader.rb`, `ref_resolver.rb`): YAML/JSON → Hash (ключи-строки); проверка `openapi: 3.x`, наличие непустого `paths`; `swagger: '2.0'` → `SpecError` с подсказкой конвертировать; резолв локальных `$ref` (`#/…`) с защитой от циклов; имя схемы сохраняется в `x-forge-ref-name`; внешние `$ref` → `UnsupportedError` с pointer | MUST |
| A-02 | **IR** (`lib/forge/ir/*.rb`): неизменяемые `Data.define` — `Spec`, `Server`, `SecurityScheme`, `Endpoint`, `Parameter`, `RequestBody`, `Response`, `Schema`. Никаких платёжных понятий. Path-level `parameters` мержатся в операции; корневой `security` подставляется при `security = nil`; `example`/`examples` объединяются; OpenAPI 3.1 `type: [..., 'null']` → тип + `nullable: true`; `allOf` → слияние; `oneOf`/`anyOf` сохраняются | MUST |
| A-03 | **Analyze** (`lib/forge/analyzers/*.rb`): анализаторы `endpoint_roles`, `auth`, `statuses`, `errors`, `webhooks`, `amount`, `fields`; каждый возвращает `Finding(key, value, confidence, source, warnings)`; фиксированный порядок запуска roles → auth → statuses → errors → webhooks → amount → fields. Ничего не знают о Ruby-коде и шаблонах | MUST |
| A-04 | Confidence ∈ [0, 1]; пороги в `rules/thresholds.yml`: ≥ 0.8 — принято без предупреждения; 0.5–0.8 — принято + WARN «low confidence»; < 0.5 — не принято, WARN «needs override» + безопасная заглушка. `source` — человекочитаемая строка-обоснование | MUST |
| A-05 | **Rules** (`rules/*.yml`): `thresholds`, `endpoint_roles`, `status_map`, `error_actions`, `field_aliases`, `amount_units`, `webhook_signature`. Всё провайдер-специфичное — только здесь или в `overrides.yml`. **Слово `novapay` в `lib/` — ошибка** (исключение: тесты и примеры) | MUST |
| A-06 | **Plan** (`lib/forge/plan/*.rb`): `IntegrationPlan` (provider, base_url, auth, operations, webhook, status_map, unmapped_statuses, error_map, amount, validations, fixtures, warnings, meta) — единственный вход рендереров; наложение `overrides.yml` с INFO `override_applied` на каждое переопределение; валидации из схемы (`minimum` суммы, `maxLength`, `pattern`, `enum`); отсутствие create-эндпоинта → `GenerationError` с подсказкой | MUST |
| A-07 | **Render** (`lib/forge/renderers/*.rb` + `templates/*.erb`): шаблоны получают только `IntegrationPlan`, никогда сырой OpenAPI-хэш; ERB `trim_mode: '-'`; нормализация пустых строк; поиск шаблона `--templates-dir/<name>.erb` → `templates/<name>.erb`, отсутствие → `GenerationError` | MUST |
| A-08 | **Verify** (`lib/forge/verifier.rb`): `ruby -c` на каждом сгенерированном `.rb`; провал → `VerificationError` с выводом компилятора; опционально `rspec` на сгенерированном spec (`-I lib`, WebMock) | MUST |
| A-09 | **Report** (`lib/forge/report.rb`): текст как в ТЗ + таблица ролей с confidence + секции Statuses / Errors / Webhook / Amount + `Warnings (N)` с уровнями WARN / UNSUPPORTED / INFO и `hint:`; `--format json` — та же структура `{spec, endpoints, auth, statuses, errors, webhook, amount, outputs, warnings}` | MUST |
| A-10 | Заглушка контракта `lib/provider/base_service.rb` (`client`, `success`/`failure`, `Result#failed?`, `approve_operation`/`reject_operation`, `credentials`, `verify_signature!` helpers), `lib/provider/http_client.rb` (Faraday с типизированными ошибками: 401 → `UnauthorizedError`, 429 → `RateLimitError`), `lib/provider/memory_operations.rb`, `Provider::Operation` | MUST |

### 4.3 Структура репозитория

```
forge/
├── bin/forge  bin/integrate  bin/e2e
├── lib/forge.rb
├── lib/forge/{cli,errors,version,loader,ref_resolver,rules,verifier,report}.rb
├── lib/forge/ir/        lib/forge/analyzers/   lib/forge/plan/
├── lib/forge/renderers/ lib/forge/fixtures/synthesizer.rb
├── lib/provider/{base_service,http_client,memory_operations}.rb
├── rules/*.yml   templates/*.erb
├── examples/specs/{novapay.yaml,cardpay.yaml,<third>.json}   examples/overrides/*.yml
├── spec/  (unit, rules, golden/<provider>/, fixtures/broken/, snapshots/, cli_spec, golden_spec)
├── docs/  (TASK, CRITERIA, CONTRACT, ARCHITECTURE, RULES, OUTPUT_FORMAT, SPEC_ANALYSIS_NOVAPAY, TEST_SPECS, AGENT_TASKS)
├── Dockerfile  Gemfile  Gemfile.lock  .rubocop.yml  .github/workflows/ci.yml  .gitignore
└── CLAUDE.md  README.md  NOTES.md
```

### 4.4 CLI и коды выхода

```
bin/forge analyze  --spec FILE [--overrides FILE] [--format text|json] [--debug]
bin/forge generate --spec FILE [--provider NAME] [--out DIR] [--overrides FILE]
                   [--templates-dir DIR] [--lang ruby] [--format text|json]
                   [--strict] [--no-verify] [--force] [--debug]
bin/forge mock     --spec FILE [--port 4567] [--webhook-url URL] [--overrides FILE]
bin/integrate      --spec FILE --provider NAME [--lang ruby]      # → forge generate --out ./output
```

| ID | Требование | Уровень |
|---|---|---|
| L-01 | `bin/forge help` показывает три команды `analyze` / `generate` / `mock` | MUST |
| L-02 | `bin/integrate` с флагами из ТЗ (`--spec`, `--provider`, `--lang ruby`) — обёртка над `forge generate --out ./output` | MUST |
| L-03 | `--lang` принимает только `ruby`; иное → exit 1 «only ruby is supported» | MUST |
| L-04 | Имя провайдера: `--provider` → иначе из `info.title` без слов API/Payout/Service, snake_case. `--provider "Nova Pay"` → `NovaPayService`, `NOVA_PAY_BASE_URL` | MUST |
| L-05 | Существующий непустой `--out` без `--force` → `GenerationError`, exit 2 | MUST |
| L-06 | `--strict` — exit 4 при наличии хотя бы одного WARN/UNSUPPORTED | SHOULD |
| L-07 | Стектрейсы только с `--debug`; без него — `error: <что не так> at <pointer> in <file>` + `hint: <что сделать>` | MUST |

| Код выхода | Когда |
|---|---|
| 0 | Успех (предупреждения допустимы) |
| 1 | Ошибка входа: файл не найден, не YAML/JSON, не OpenAPI 3.x, нерезолвимый `$ref`, нет `paths`, `--lang` ≠ ruby |
| 2 | Ошибка генерации: нет create-эндпоинта, шаблон не найден, `--out` занят без `--force` |
| 3 | Сгенерированный код не прошёл `ruby -c` или его spec красный |
| 4 | `--strict` и есть хотя бы один WARN/UNSUPPORTED |

### 4.5 Иерархия ошибок

```ruby
module Forge
  class Error < StandardError; attr_reader :pointer, :hint; end
  class SpecError < Error; end          # exit 1
  class UnsupportedError < Error; end   # exit 1 если фатально; иначе → Warning(:unsupported)
  class GenerationError < Error; end    # exit 2
  class VerificationError < Error; end  # exit 3
end
```

Каждое сообщение — с контекстом (файл, JSON-pointer) и подсказкой «что сделать».

### 4.6 Требования к анализу спеки (что должно распознаваться)

| ID | Анализатор | Требование | Уровень |
|---|---|---|---|
| N-01 | `EndpointRoles` | Роли `create`, `status`, `cancel`, `balance`, `webhook`, `other` по очкам за HTTP-метод, слова в path/operationId/summary/tags, path-параметр, `security: []`, header с `signature`. Один эндпоинт — одна роль; конфликт → больший счёт побеждает, второй → `other` + WARN | MUST |
| N-02 | `Auth` | apiKey/header → `api_key` header; http bearer → `Authorization: Bearer <token>`; http basic → login+password; oauth2 → UNSUPPORTED (генерируется bearer с TODO); apiKey в query → WARN | MUST |
| N-03 | `Statuses` | Поиск enum-поля статуса (`status`, `state` …) в ответе status/create и webhook; каждый элемент → `status_map.yml` (case-insensitive, `-`/`_` нормализуются); unmapped → WARN. Ядро словаря — канон Q-06 + синонимы (NEW, SUCCESS, DECLINED, ON_HOLD, captured …) | MUST |
| N-04 | `Errors` | По всем responses create/status/cancel: код провайдера из `examples` или enum поля `code`; действие из `error_actions.yml` по HTTP и коду; `Retry-After` распознан | MUST |
| N-05 | `Webhooks` | Источники: эндпоинт роли webhook, `callbacks`, top-level `webhooks` (3.1). Заголовок — header-параметр с `sign` в имени; алгоритм — regex `HMAC[-_ ]?(SHA-?(256|512|1))` по description; кодировка — `hex` по умолчанию, `base64` если упомянуто; `event_map` по суффиксу события или полю статуса в примере; поле события `event` или `type` | MUST |
| N-06 | `Amount` | Маркеры единиц из `amount_units.yml` в description («копейки», «cents», «minor units»); `integer` + `minimum ≥ 1000` → minor; `string`/`number` с десятичным `pattern` → major; ничего → major + WARN. Выход: field, unit, multiplier, minimum_major, currency_field, currencies, type | MUST |
| N-07 | `Fields` | Каждое свойство request-схемы → `field_aliases.yml` → выражение `operation.*`; вложенные объекты рекурсивно; неизвестное → `nil` + `# TODO(forge)` + WARN; обязательность из `required`; условная обязательность из description → WARN `conditional_required` + `.compact` | MUST |
| N-08 | Общее | Неподдерживаемое (Swagger 2.0, внешние `$ref`, OAuth2-флоу, `oneOf`/`anyOf` глубже первого уровня, XML, multipart, подпись с timestamp) — UNSUPPORTED в отчёте, не падение; критичное → `NotImplementedError`/TODO в коде, а не тихая заглушка | MUST |

Ожидаемый результат `analyze` на NovaPay (эталон для снапшот-теста):

```
Parsing spec... ok (openapi 3.0.3, NovaPay Payout API 1.0.0)
Found 5 endpoints: POST /payouts, GET /payouts/{id}, POST /payouts/{id}/cancel,
POST /webhooks/payout, GET /balance
  create   POST /payouts                      createPayout     confidence 0.95
  status   GET /payouts/{payout_id}           getPayoutStatus  confidence 0.90
  cancel   POST /payouts/{payout_id}/cancel   cancelPayout     confidence 0.95
  webhook  POST /webhooks/payout              payoutWebhook    confidence 0.90
  balance  GET /balance                       getBalance       confidence 0.85
Auth: ApiKeyAuth (header: X-API-Key)
Statuses: pending, processing → in_progress; completed → approved; failed, cancelled → rejected
Errors: 400 validation_error → reject; 401 unauthorized → alert; 402 insufficient_balance → retry; …
Webhook signature: X-NovaPay-Signature (HMAC-SHA256, hex)
Amount: integer, minor units (×100), min 1000 RUB — source: description "в копейках", minimum 100000
```

Инварианты NovaPay: 5 эндпоинтов и 5 ролей; auth apiKey/`X-API-Key`; 5 статусов в карте, 0 unmapped; карта
ошибок 8 строк, `Retry-After` распознан; 7 findings; **ровно 5 предупреждений** (в т.ч. `conditional_required`
для `bank_code`/`card_number`, INFO для `GET /balance` вне контракта); NovaPay генерируется **без overrides**.

### 4.7 Выходные файлы `output/<provider>/`

| ID | Файл | Требование | Уровень |
|---|---|---|---|
| O-01 | `<provider>_service.rb` | По п. 1.4.1 (S-01…S-12). Дополнительно: `request_method` используется для ветки реквизитов и делегирования `status`/`check` → `fetch_status`; план без webhook → `process_callback` с `not_implemented`; без cancel → нет `cancel_request`; major units → `'%.2f'`; balance/cancel — необязательные хелперы | MUST |
| O-02 | `INTEGRATION.md` | По п. 1.4.2 (D-01…D-07) | MUST |
| O-03 | `fixtures.json` | По п. 1.4.3 (F-01…F-05); `JSON.pretty_generate` | MUST |
| O-04 | `<provider>_service_spec.rb` | RSpec на WebMock и фикстурах: create 201/422, fetch_status, callback approved/rejected, проверка подписи; зелёный на novapay и cardpay | SHOULD |
| O-05 | `mock_server.rb` | Sinatra-мок провайдера из той же спеки: 401 без ключа, 422 на малую сумму, 201 + статус, `POST /_simulate/:id/<status>` шлёт подписанный webhook | SHOULD |
| O-06 | `report.txt` | Копия отчёта `analyze`/`generate` с Warnings | MUST |
| O-07 | Все `.rb` проходят `ruby -c`; сгенерированный сервис загружается (`require`) вместе с `lib/provider` без ошибок | MUST |
| O-08 | Заголовок файлов — только версия forge и имя спеки (без времени) | MUST |

### 4.8 Overrides

| ID | Требование | Уровень |
|---|---|---|
| V-01 | `overrides.yml` — общий механизм, ключи в терминах экспертов: `amount_unit` (minor/major), `fields.<path>.required` / `required_if` (`{field: type, equals: sbp}`), `webhook.signature_encoding` (hex/base64), `webhook.signature_payload` (raw_body/fields), `statuses`, `endpoints.<operationId>: <role>`, `errors`, `events` | MUST |
| V-02 | Неизвестный ключ → `SpecError` с подсказкой «did you mean» | SHOULD |
| V-03 | `examples/overrides/<provider>.yml` с комментариями для каждой тестовой спеки; `overrides.yml.example` строка на каждый WARN | SHOULD |
| V-04 | `--overrides` работает в `analyze`, `generate`, `mock` | MUST |

### 4.9 Универсальность — тестовые спеки

| ID | Спека | Что проверяет | DoD | Уровень |
|---|---|---|---|---|
| U-01 | `examples/specs/novapay.yaml` (= `provider_api.yaml`) | Эталон ТЗ | Golden совпадает с reference из ТЗ; 0 overrides; 5 WARN/INFO | MUST |
| U-02 | `examples/specs/cardpay.yaml` | Bearer auth; выплата на карту; сумма в рублях строкой (major); статусы NEW/SUCCESS/DECLINED/ON_HOLD в поле `state`; обёртка `data` с suffix-поиском id; webhook через `callbacks`; HMAC-SHA512 base64; событие в поле `type`; production-сервер первым; нет cancel | Без overrides — 8 ожидаемых WARN; с overrides — 3 INFO, 0 WARN; сгенерированный spec зелёный | MUST |
| U-03 | Третья спека (OpenAPI 3.1 **JSON**, другой payout-провайдер) | Top-level `webhooks`; `oneOf` (первый вариант + WARN); `allOf`; 3.1 массив типов; basic auth; `application/problem+json`; внешний `$ref` → UNSUPPORTED без падения; подпись с timestamp → UNSUPPORTED + `NotImplementedError` в `verify_signature!` | Секция UNSUPPORTED — 3 пункта; exit 0 | SHOULD |
| U-04 | `spec/fixtures/broken/*.yaml` (8 файлов) | Битые спеки: не YAML, нет `openapi`, `swagger: 2.0`, нет `paths`, нерезолвимый `$ref`, циклический `$ref`, внешний `$ref`, нет create-эндпоинта | Ожидаемый класс ошибки, сообщение с pointer и hint, правильный exit-код | MUST |

Все анализаторы исправляются в словарях/анализаторах, **не в шаблонах под конкретный случай**.

### 4.10 Стандарты кода

| ID | Требование | Уровень |
|---|---|---|
| K-01 | Без метапрограммирования (`define_method`, `method_missing`, `instance_eval`) — код читается без Ruby-опыта | MUST |
| K-02 | Файлы < 200 строк; один класс — одна ответственность; никаких `utils.rb`/`helpers.rb` | MUST |
| K-03 | `.rubocop.yml`: TargetRubyVersion 3.3, Metrics/MethodLength 20, Metrics/ClassLength 200, Style/Documentation off, длина строки 120; `bundle exec rubocop` — 0 нарушений | MUST |
| K-04 | Тесты пишутся вместе с модулем; `bundle exec rspec` зелёный | MUST |
| K-05 | Golden-тесты `spec/golden/<provider>/` сравниваются байт-в-байт (нормализуя перевод строки); обновление только через `UPDATE_GOLDEN=1` с просмотром диффа | MUST |
| K-06 | Коммит после каждой зелёной задачи; сообщение `<модуль>: <что сделано>` на английском | SHOULD |
| K-07 | Архитектурные решения фиксируются в `NOTES.md` (раздел «Решения»); изменения CLI — в `README.md` | SHOULD |

### 4.11 Тестирование и CI

| Уровень | Что | Где |
|---|---|---|
| Unit | loader, ref_resolver, каждый анализатор на мини-спеках из литералов | `spec/**/*_spec.rb` |
| Правила | каждый словарь: синонимы, пороги | `spec/rules/` |
| Reference | все элементы примера ТЗ присутствуют в сгенерированном сервисе | `spec/reference_spec.rb` |
| Golden | `generate` на `examples/specs/*` → сравнение с `spec/golden/<provider>/` | `spec/golden_spec.rb` |
| Негативные | битые спеки → ошибки и exit-коды | `spec/fixtures/broken/*`, `spec/cli_spec.rb` |
| Снапшот | вывод `analyze` на novapay | `spec/snapshots/novapay_analyze.txt` |
| Сгенерированный код | его собственный spec (WebMock) | `output/<p>/<p>_service_spec.rb` |
| e2e | мок-сервер + сервис + webhook-приёмник: create → fetch_status → simulate completed → `operation approved ✓` | `bin/e2e`, отдельный CI job |

CI (`.github/workflows/ci.yml`): rubocop, rspec, `generate` ×3 спеки, запуск сгенерированных spec, e2e.

### 4.12 Упаковка и документация проекта

| ID | Требование | Уровень |
|---|---|---|
| P-01 | `Dockerfile` (`ruby:3.3-slim`, `bundle install`, ENTRYPOINT `bin/forge`); `docker build` и `docker run` проверены с нуля | MUST |
| P-02 | `README.md`: что делает инструмент; схема пайплайна; запуск одной командой (Docker и без); реальный вывод `analyze`; паттерны и почему такие решения; overrides; таблица «критерий → где посмотреть в репозитории»; раздел «дополнительные идеи» (генерируемый RSpec, мок-сервер, e2e, отчёт с confidence, «подход подтверждён организаторами»); что не поддерживается; что дальше (pay-in, Swagger 2.0). Без пометок «(план)» у реализованного | MUST |
| P-03 | `docs/CONTRACT.md` — контракт BaseService и модель operation с семантикой `request_method` | MUST |
| P-04 | `docs/RULES.md`, `docs/OUTPUT_FORMAT.md`, `docs/ARCHITECTURE.md`, `docs/TEST_SPECS.md` актуальны реализации | SHOULD |
| P-05 | Тег `v1.0.0` до стоп-кода; свежий `git clone` + `docker build` + одна команда из README дают результат | MUST |

### 4.13 Что сознательно не делаем

Swagger 2.0; внешние `$ref`; OAuth2-флоу (bearer с TODO); `oneOf`/`anyOf` глубже первого уровня; XML-тела;
multipart; GraphQL; pay-in/депозиты; веб-интерфейс; вызов реального провайдера. Всё это — UNSUPPORTED или
раздел «что дальше», не падение.

---

## 5. Этапы и DoD [FORGE]

| Этап | Срок (ALA) | DoD |
|---|---|---|
| M1 Analyze | пт 4.09 утро | `bin/forge analyze --spec examples/specs/novapay.yaml` печатает 5 эндпоинтов с ролями, auth, статусы, ошибки, webhook + подпись; битый YAML → понятная ошибка, exit 1 |
| M2 Generate NovaPay | пт 4.09 вечер | `bin/forge generate` создаёт сервис, spec, `INTEGRATION.md`, `fixtures.json`, `report.txt`; `ruby -c` ok; reference- и golden-тесты зелёные; сгенерированный spec зелёный; `bin/integrate` работает |
| M3 Universal | сб 5.09 | cardpay и третья спека дают корректный вывод с ожидаемыми WARN/UNSUPPORTED; `overrides.yml` их закрывает; матрица покрытия TEST_SPECS зелёная |
| M4 Proof | сб 5.09 вечер | `bin/e2e examples/specs/novapay.yaml` → `operation approved ✓`; то же для cardpay |
| M5 Ship | вс 6.09 до 20:00 | Docker, CI, README, rubocop чистый, тег `v1.0.0`; последний пуш до 00:00 ALA |

---

## 6. Чек-лист приёмки: критерий жюри → где проверять

| Критерий техжюри | Артефакт / команда |
|---|---|
| 1. Разбор спеки (20) | `bin/forge analyze`, `report.txt`, `lib/forge/analyzers/`, `rules/`, `spec/analyzers/` |
| 2. Генерация сервиса (25) | `output/<p>/<p>_service.rb`, `templates/service.rb.erb`, `lib/provider/base_service.rb`, `docs/CONTRACT.md`, `bin/e2e` |
| 3. Преобразование данных (15) | `STATUS_MAP`, `ERROR_MAP`, `build_payout_payload`, `rules/field_aliases.yml`, `rules/amount_units.yml`, `check_conditions` |
| 4. Универсальность (10) | `examples/specs/cardpay.yaml` + третья спека, `spec/golden/`, `examples/overrides/`, `--templates-dir`, секции WARN/UNSUPPORTED |
| 5. Документация и фикстуры (13) | `INTEGRATION.md` (+ «Допущения»), `fixtures.json`, `<p>_service_spec.rb` |
| 6. Удобство и демо (10) | `bin/integrate`, `bin/forge generate`, `Dockerfile`, вывод и exit-коды, `README.md` |
| 7. Качество (10) | `lib/` структура, `lib/forge/errors.rb`, `spec/fixtures/broken/`, `rubocop`, CI, README-инструкция |
| Отраслевое: доп. идеи (6) | генерируемый RSpec, мок-сервер, e2e, confidence-отчёт, overrides — раздел в README и слайд |
| Отраслевое: полнота (8) | все 4 выхода ТЗ + spec/mock/report; 3 спеки; негативные тесты |

---

## 7. Быстрая проверка (команды)

```bash
bundle exec rubocop                                   # 0 нарушений
bundle exec rspec                                     # зелёный
bin/forge analyze  --spec examples/specs/novapay.yaml # 5 эндпоинтов, auth, статусы, ошибки, webhook, 5 warnings
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/novapay        # exit 0, 6 файлов
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/novapay        # exit 2 (без --force)
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/novapay --strict --force  # exit 4
bin/forge generate --spec examples/specs/cardpay.yaml --out tmp/cardpay        # 8 WARN
bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --out tmp/cardpay --force  # 3 INFO, 0 WARN
bin/forge generate --spec spec/fixtures/broken/swagger2.yaml --out tmp/x       # exit 1 + hint
bin/integrate --spec provider_api.yaml --provider novapay --lang ruby          # вывод как в ТЗ
bin/integrate --spec provider_api.yaml --provider novapay --lang python        # exit 1
ruby -c tmp/novapay/novapay_service.rb
bundle exec rspec -I lib tmp/novapay/novapay_service_spec.rb
bin/e2e examples/specs/novapay.yaml                   # operation approved ✓
docker build -t forge . && docker run --rm -v $PWD:/work forge generate --spec /work/provider_api.yaml --out /work/output
grep -ri novapay lib/                                 # пусто
git log --format='%ci' -1                             # раньше 2026-09-06 22:00 +0300
```
