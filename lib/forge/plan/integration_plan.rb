# frozen_string_literal: true

module Forge
  module Plan
    # Единственный вход рендереров (docs/ARCHITECTURE.md → Plan). Никакого времени и путей машины.
    IntegrationPlan = Data.define(:provider, :base_url, :auth, :operations, :webhook, :status_map, :unmapped_statuses,
                                  :event_map, :error_map, :success_statuses, :amount, :requisite_types, :fields,
                                  :validations, :gateway_config, :fixtures, :outside_contract, :warnings, :meta)

    # rubocop:disable-next Lint/DataDefineOverride -- `method` задан docs/ARCHITECTURE.md (HTTP-verb)
    OperationPlan = Data.define(:role, :method, :path, :path_params, :headers, :body_encoding, :success_statuses,
                                :response_id_path, :response_status_path, :error_statuses)
  end
end
