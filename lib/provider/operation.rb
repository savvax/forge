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

    # Имя из примера ТЗ; на платформе поле называется provider_operation_key (QA 2).
    alias_method :provider_operation_id, :provider_operation_key
  end

  Record = Data.define(:name, :credentials, :config) do
    def initialize(name:, credentials: {}, config: {})
      super
    end
  end
end
