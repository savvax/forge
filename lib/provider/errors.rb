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

  # 401
  class UnauthorizedError < HttpError; end
  # 5xx
  class ServerError < HttpError; end

  # 429
  class RateLimitError < HttpError
    attr_reader :retry_after

    def initialize(response, retry_after: nil)
      @retry_after = retry_after&.to_i
      super(response, "rate limited, retry after #{@retry_after.inspect} seconds")
    end
  end

  # таймаут, DNS, отказ соединения
  class ConnectionError < Error; end
  # подпись webhook не совпала
  class SignatureError < Error; end
end
