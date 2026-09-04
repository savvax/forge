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

    def find_by_provider_id(provider_operation_id)
      @by_id.values.find { |op| op.provider_operation_id == provider_operation_id }
    end

    def update(id, status: nil, provider_status: nil, error_code: nil, provider_operation_id: nil)
      operation = @by_id.fetch(id)
      operation.status = status if status
      operation.provider_status = provider_status if provider_status
      operation.error_code = error_code if error_code
      operation.provider_operation_id = provider_operation_id if provider_operation_id
      operation
    end
  end
end
