# Контракт `Provider::BaseService`

Зачем читать: реальный класс Space Payments нам не дадут (QA 1). Этот документ — **наш контракт**:
заглушка `lib/provider/*`, против которой генерируются и тестируются сервисы. Всё, что генератор
знает о «платформе», описано здесь. Renderers генерируют код только под этот контракт.

## 1. Сигнатуры из ТЗ и их смысл

```ruby
class Provider::ExampleService < Provider::BaseService
  def check_conditions(operation, request_method)  # предпроверки → Result
  def create_request(operation, request_method)    # создание выплаты → Result
  def process_callback(payload)                    # обработка webhook → Result
  def fetch_status(operation)                      # статус-запрос → Result
end
```

| Аргумент | Что это | Источник |
|---|---|---|
| `operation` | Объект выплаты платформы (`Provider::Operation`) | ТЗ (`operation.amount`, `operation.id`, `operation.payout_requisite`, `operation.provider_operation_key` — имя поля платформы по QA 2; `provider_operation_id` из примера ТЗ оставлен алиасом) |
| `request_method` | **Логический тип действия, не HTTP-verb**: платёжный метод шлюза (`'sbp'`, `'card'`, `'bank_account'`) или служебное `'status'`/`'check'`; ТЗ показывает default `'create'` | QA 1, письменный ответ |
| `payload` | Разобранный JSON тела webhook (Hash, строковые ключи) | ТЗ |
| `raw_body:`, `headers:` | Сырое тело и заголовки webhook для проверки подписи (kwargs с default — вызов `process_callback(payload)` из ТЗ остаётся валидным) | решение D-03 |

Правило для `request_method` в сгенерированном коде:
- `'status'`/`'check'` → `create_request` делегирует в `fetch_status`;
- значение из `REQUISITE_TYPES` (enum поля `recipient.type` спеки) → используется как тип реквизитов;
- иначе (`'create'`, `nil`) → тип реквизитов = первый ключ `operation.payout_requisite`, входящий в `REQUISITE_TYPES`.

## 2. `Result`

```ruby
Provider::Result = Data.define(:status, :code, :data)
# status: :ok | HTTP-like символ (:unprocessable_entity, :unauthorized, :too_many_requests, :bad_gateway, :not_found, …)
# code:   nil | строка ('amount_too_low', 'provider.rate_limit', 'invalid_signature', 'unknown_event')
# data:   Hash (status:, provider_status:, provider_operation_key:, result: { id: }, retry_after:, message:, provider_code:)
#         result[:id] — ID у провайдера: платформа делает provider_operation_key = payload.dig(:result, :id) (QA 2)
```

`success(data = {})` → `status: :ok`; `failure(status, code, data = {})`. `success?` / `failed?`.
Коды ошибок провайдера всегда с префиксом `provider.` (`provider.validation_error`), коды наших
предпроверок — без префикса (`amount_too_low`, `requisite_missing`).

## 3. `Operation`

```ruby
Provider::Operation = Struct.new(
  :id,                    # String — ID операции на нашей стороне ('op_abc123'); уходит провайдеру как external_id
  :amount,                # BigDecimal/Numeric в мажорных единицах (1500.00 RUB). В минорные переводит сервис
  :currency,              # 'RUB'
  :status,                # 'new' | 'in_progress' | 'approved' | 'rejected'
  :provider_operation_key, # ID у провайдера ('np_7f3a9b2c'), появляется после create_request
  :provider_status,       # сырой статус провайдера ('processing')
  :error_code,            # код ошибки при rejected ('recipient_not_found')
  :payout_requisite,      # Hash реквизитов по типам (см. ниже)
  :idempotency_key,       # UUID, стабильный для операции (для Idempotency-Key)
  :description,           # назначение платежа (может быть nil)
  :customer,              # Hash: 'email', 'phone', 'name', 'ip' (может быть nil)
  keyword_init: true
)
```

Канонические реквизиты (`payout_requisite`): ключ — тип, значение — Hash строковых ключей.

| Тип | Поля |
|---|---|
| `sbp` | `phone` (`7XXXXXXXXXX`), `bank_code` (БИК), `bank_name` |
| `card` | `number` (PAN), `holder`, `expiry_month`, `expiry_year`, `phone` |
| `bank_account` | `account_number`, `bank_code`, `bank_name`, `iban`, `bic`, `holder`, `country` |
| `wallet` | `id`, `provider`, `phone` |

Словарь `rules/field_aliases.yml` переводит поля провайдера в выражения `operation.payout_requisite.dig(<type>, '<field>')`.

## 4. `Provider::Record` (провайдер в базе платформы)

```ruby
Provider::Record = Data.define(:name, :credentials, :config)
# credentials: {'api_key' => …, 'callback_secret' => …, 'token' => …, 'login' => …, 'password' => …, 'merchant_id' => …}
# config:      {'base_url' => …, 'callback_url' => 'https://spacepayments.example/webhooks/novapay'}
```

Секретов в спеке нет → сгенерированный `INTEGRATION.md` перечисляет, какие ключи `credentials`
нужно заполнить вручную.

## 5. Полный код заглушки

Файлы `lib/provider/*.rb`. Это код, который агент T10 кладёт в репозиторий (с тестами `spec/provider/`).

### `lib/provider/errors.rb`

```ruby
# frozen_string_literal: true

module Provider
  class Error < StandardError; end

  # Ошибка HTTP-уровня: несёт ответ провайдера.
  class HttpError < Error
    attr_reader :response

    def initialize(response, message = nil)
      @response = response
      super(message || "provider responded with HTTP #{response.status}")
    end

    def status
      response.status
    end
  end

  class UnauthorizedError < HttpError; end   # 401
  class ServerError < HttpError; end         # 5xx

  class RateLimitError < HttpError           # 429
    attr_reader :retry_after

    def initialize(response, retry_after: nil)
      @retry_after = retry_after&.to_i
      super(response, "rate limited, retry after #{@retry_after.inspect} seconds")
    end
  end

  class ConnectionError < Error; end         # таймаут, DNS, отказ соединения
  class SignatureError < Error; end          # подпись webhook не совпала
end
```

### `lib/provider/result.rb`

```ruby
# frozen_string_literal: true

module Provider
  Result = Data.define(:status, :code, :data) do
    def success?
      status == :ok
    end

    def failed?
      !success?
    end
  end
end
```

### `lib/provider/operation.rb`

```ruby
# frozen_string_literal: true

require 'securerandom'

module Provider
  Operation = Struct.new(:id, :amount, :currency, :status, :provider_operation_key, :provider_status,
                         :error_code, :payout_requisite, :idempotency_key, :description, :customer,
                         keyword_init: true) do
    def initialize(**attrs)
      super
      self.status ||= 'new'
      self.payout_requisite ||= {}
      self.idempotency_key ||= SecureRandom.uuid
    end
  end

  Record = Data.define(:name, :credentials, :config) do
    def initialize(name:, credentials: {}, config: {})
      super
    end
  end
end
```

### `lib/provider/memory_operations.rb`

```ruby
# frozen_string_literal: true

module Provider
  # In-memory хранилище операций для тестов, e2e и мок-демо.
  # Платформа подставит своё хранилище с тем же интерфейсом.
  class MemoryOperations
    def initialize
      @by_id = {}
    end

    def save(operation)
      @by_id[operation.id] = operation
    end

    def find(id)
      @by_id[id]
    end

    def find_by_provider_id(provider_operation_key)
      @by_id.values.find { |op| op.provider_operation_key == provider_operation_key }
    end

    def update(id, status: nil, provider_status: nil, error_code: nil, provider_operation_key: nil)
      operation = @by_id.fetch(id)
      operation.status = status if status
      operation.provider_status = provider_status if provider_status
      operation.error_code = error_code if error_code
      operation.provider_operation_key = provider_operation_key if provider_operation_key
      operation
    end
  end
end
```

### `lib/provider/http_client.rb`

```ruby
# frozen_string_literal: true

require 'faraday'
require 'json'

module Provider
  # Тонкая обёртка над Faraday: JSON/form тела, разбор ответа, типизированные ошибки.
  # 401 → UnauthorizedError, 429 → RateLimitError, 5xx → ServerError, сеть → ConnectionError.
  # Прочие 4xx возвращаются как Response — их интерпретирует сервис через ERROR_MAP.
  class HttpClient
    Response = Data.define(:status, :body, :headers)

    def initialize(connection: nil, timeout: 10, open_timeout: 5)
      @connection = connection || Faraday.new do |f|
        f.options.timeout = timeout
        f.options.open_timeout = open_timeout
        f.adapter Faraday.default_adapter
      end
    end

    def get(url, headers: {}, params: {})
      perform(:get, url, headers: headers, params: params)
    end

    def post(url, json: nil, form: nil, headers: {})
      perform(:post, url, headers: headers, json: json, form: form)
    end

    def delete(url, headers: {})
      perform(:delete, url, headers: headers)
    end

    private

    def perform(verb, url, headers:, json: nil, form: nil, params: {})
      raw = @connection.run_request(verb, url, encode_body(json, form), content_headers(json, form).merge(headers)) do |req|
        req.params.update(params) unless params.empty?
      end
      response = Response.new(status: raw.status, body: parse_body(raw.body), headers: raw.headers.to_h)
      raise_for_status!(response)
      response
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise ConnectionError, "#{verb.upcase} #{url}: #{e.message}"
    end

    def encode_body(json, form)
      return JSON.generate(json) if json
      return URI.encode_www_form(form) if form

      nil
    end

    def content_headers(json, form)
      return { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } if json
      return { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' } if form

      { 'Accept' => 'application/json' }
    end

    def parse_body(body)
      return {} if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      { 'raw' => body }
    end

    def raise_for_status!(response)
      case response.status
      when 401 then raise UnauthorizedError, response
      when 429 then raise RateLimitError.new(response, retry_after: response.headers['retry-after'])
      when 500..599 then raise ServerError, response
      end
    end
  end
end
```

### `lib/provider/base_service.rb`

```ruby
# frozen_string_literal: true

require 'openssl'

module Provider
  # Контракт сервиса провайдера. Сгенерированные сервисы переопределяют четыре метода контракта
  # и пользуются хелперами ниже. Всё, что здесь, платформа предоставляет «из коробки».
  class BaseService
    INTERNAL_STATUSES = %w[new in_progress approved rejected].freeze

    HTTP_STATUS_SYMBOLS = {
      400 => :bad_request, 401 => :unauthorized, 402 => :payment_required, 403 => :forbidden,
      404 => :not_found, 409 => :conflict, 422 => :unprocessable_entity, 429 => :too_many_requests,
      500 => :internal_server_error, 502 => :bad_gateway, 503 => :service_unavailable, 504 => :gateway_timeout
    }.freeze

    attr_reader :provider, :operations, :client

    def initialize(provider:, operations: MemoryOperations.new, client: HttpClient.new)
      @provider = provider
      @operations = operations
      @client = client
    end

    # --- Контракт -------------------------------------------------------------

    def check_conditions(operation, _request_method)
      return failure(:unprocessable_entity, 'amount_invalid') unless operation.amount.to_d.positive?
      return failure(:unprocessable_entity, 'requisite_missing') if operation.payout_requisite.empty?

      success
    end

    def create_request(_operation, _request_method = 'create')
      raise NotImplementedError, "#{self.class}#create_request"
    end

    def fetch_status(_operation)
      raise NotImplementedError, "#{self.class}#fetch_status"
    end

    def process_callback(_payload, raw_body: nil, headers: {})
      raise NotImplementedError, "#{self.class}#process_callback"
    end

    # --- Результаты -----------------------------------------------------------

    def success(data = {})
      Result.new(status: :ok, code: nil, data: data)
    end

    def failure(status, code, data = {})
      Result.new(status: status, code: code, data: data)
    end

    # --- Переходы статуса операции (по ID провайдера, как в примере ТЗ) -------

    def approve_operation(provider_operation_key)
      transition_by_provider_id(provider_operation_key, 'approved')
    end

    def reject_operation(provider_operation_key, error_code = nil)
      transition_by_provider_id(provider_operation_key, 'rejected', error_code: error_code)
    end

    def mark_in_progress(provider_operation_key)
      transition_by_provider_id(provider_operation_key, 'in_progress')
    end

    # --- Доступ к настройкам --------------------------------------------------

    def credentials
      provider.credentials
    end

    def config
      provider.config
    end

    def callback_url
      config.fetch('callback_url')
    end

    private

    def transition(operation, status, provider_status: nil, error_code: nil, provider_operation_key: nil)
      operations.update(operation.id, status: status, provider_status: provider_status,
                                      error_code: error_code, provider_operation_key: provider_operation_key)
      key = provider_operation_key || operation.provider_operation_key
      success(status: status, provider_status: provider_status, error_code: error_code,
              provider_operation_key: key, result: { id: key }) # платформа читает payload.dig(:result, :id)
    end

    def transition_by_provider_id(provider_operation_key, status, error_code: nil)
      operation = operations.find_by_provider_id(provider_operation_key)
      return failure(:not_found, 'operation_not_found', provider_operation_key: provider_operation_key) unless operation

      transition(operation, status, error_code: error_code)
    end

    def http_symbol(status)
      HTTP_STATUS_SYMBOLS.fetch(status) { :"http_#{status}" }
    end

    # Ищет заголовок без учёта регистра, включая Rack-форму HTTP_X_NOVAPAY_SIGNATURE.
    def header_value(headers, name)
      wanted = [name.downcase, "http_#{name.tr('-', '_')}".downcase]
      headers.each { |key, value| return value if wanted.include?(key.to_s.downcase) }
      nil
    end

    def secure_compare(given, expected)
      return false if given.nil? || expected.nil?

      OpenSSL.secure_compare(given.to_s, expected.to_s)
    end
  end
end
```

`amount.to_d` требует `require 'bigdecimal/util'` в `lib/provider.rb`. Файл `lib/provider.rb`
подключает все части в правильном порядке.

## 6. Как сгенерированный сервис использует контракт

| Что делает сервис | Через что |
|---|---|
| Отправляет запрос | `client.post(url, json:, headers:)`, `client.get(url, headers:)` |
| Читает секреты | `credentials.fetch('api_key')`, `credentials.fetch('callback_secret')` |
| Сохраняет ID провайдера и статус после create | `transition(operation, 'in_progress', provider_status:, provider_operation_key:)` |
| Применяет статус из ответа/статус-запроса | `apply_status(operation, provider_status)` (генерируется; внутри `STATUS_MAP` + `transition`) |
| Обрабатывает webhook | `EVENT_MAP` → `approve_operation` / `reject_operation` / `mark_in_progress` по `payload[id_field]` |
| Проверяет подпись | `verify_signature!(raw_body, headers)` (генерируется; `OpenSSL::HMAC`, `secure_compare`) |
| Классифицирует HTTP-ошибку | `http_symbol(status)` + `ERROR_MAP` |

## 7. Тесты заглушки (`spec/provider/`)

- `Result`: `success?`, `failed?`.
- `Operation`: default `status 'new'`, `idempotency_key` UUID, `payout_requisite {}`.
- `MemoryOperations`: save/find/find_by_provider_id/update.
- `HttpClient` (WebMock): 200 JSON → Response; 401 → `UnauthorizedError`; 429 с `Retry-After: 60` →
  `RateLimitError#retry_after == 60`; 503 → `ServerError`; таймаут → `ConnectionError`; невалидный JSON → `{'raw' => …}`;
  `form:` → `Content-Type: application/x-www-form-urlencoded`.
- `BaseService`: `check_conditions` (amount 0 → `amount_invalid`; пустые реквизиты → `requisite_missing`);
  `approve_operation` неизвестного ID → `operation_not_found`; `header_value` находит `HTTP_X_SIGNATURE`;
  `secure_compare(nil, 'x') == false`.

## 8. Что платформа могла бы добавить (не делаем, но упоминаем в README → «Что дальше»)

Retry с backoff по `retry_after`, circuit breaker на 5xx, очередь webhook'ов, alert ops на 401 —
в сгенерированном коде эти события уже приходят в виде `Result` с кодом и `action` из `ERROR_MAP`,
платформа решает, что с ними делать.
