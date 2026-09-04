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

    def approve_operation(provider_operation_id)
      transition_by_provider_id(provider_operation_id, 'approved')
    end

    def reject_operation(provider_operation_id, error_code = nil)
      transition_by_provider_id(provider_operation_id, 'rejected', error_code: error_code)
    end

    def mark_in_progress(provider_operation_id)
      transition_by_provider_id(provider_operation_id, 'in_progress')
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

    def transition(operation, status, provider_status: nil, error_code: nil, provider_operation_id: nil)
      operations.update(operation.id, status: status, provider_status: provider_status,
                                      error_code: error_code, provider_operation_id: provider_operation_id)
      success(status: status, provider_status: provider_status, error_code: error_code,
              provider_operation_id: provider_operation_id || operation.provider_operation_id)
    end

    def transition_by_provider_id(provider_operation_id, status, error_code: nil)
      operation = operations.find_by_provider_id(provider_operation_id)
      return failure(:not_found, 'operation_not_found', provider_operation_id: provider_operation_id) unless operation

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
