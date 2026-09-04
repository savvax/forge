# frozen_string_literal: true

require_relative 'integration_plan'
require_relative 'naming'
require_relative 'validations'
require_relative 'fixtures'

module Forge
  module Plan
    # findings (+ overrides) → IntegrationPlan. Overrides подключаются в T09 (пока identity).
    class Builder
      HELPERS = { cancel: 'cancel_request', balance: 'fetch_balance' }.freeze
      SANDBOX = /sandbox|test|staging|dev/i
      PRODUCTION = /prod|live/i
      HINT_CREATE = 'set endpoints.<operationId>: create (overrides.yml)'

      def self.build(spec, findings, overrides: nil, provider_name: nil)
        new(spec, findings, overrides, provider_name).build
      end

      def initialize(spec, findings, overrides, provider_name)
        @spec = spec
        @f = findings
        @overrides = overrides
        @provider_name = provider_name
      end

      def build
        ensure_create!
        parts = base_parts.merge(operations_parts).merge(errors_parts)
        parts[:fixtures] = Fixtures.new(@spec, @f, parts).build
        IntegrationPlan.new(**parts)
      end

      private

      def roles = @f[:endpoint_roles].value
      def rows = @f[:errors].value[:rows]
      def value(key) = @f[key].value

      def ensure_create!
        return if roles[:create]

        raise GenerationError.new('no create endpoint found in the spec', file: @spec.source_path,
                                                                          hint: HINT_CREATE)
      end

      def base_parts
        provider = provider_naming
        { provider: provider, base_url: base_url(provider).merge(override('base_url')), auth: value(:auth),
          amount: value(:amount), fields: value(:fields), requisite_types: value(:fields)[:requisite_types],
          validations: Validations.build(value(:fields), value(:amount)), gateway_config: gateway_config,
          outside_contract: outside_contract, warnings: @f.values.flat_map(&:warnings), meta: meta }
          .merge(status_parts)
      end

      def status_parts
        webhooks = value(:webhooks)
        { webhook: webhooks[:endpoint] && webhooks, event_map: webhooks[:event_map],
          status_map: value(:statuses)[:map], unmapped_statuses: value(:statuses)[:unmapped] }
      end

      def operations_parts
        ops = HELPERS.keys.unshift(:create, :status).to_h { |role| [role, roles[role] && operation(role, roles[role])] }
        { operations: ops, success_statuses: ops[:create].success_statuses }
      end

      def errors_parts
        relevant = rows.reject { |r| r[:action] == 'treat_as_success' || r[:role] == :cancel }
        map = relevant.sort_by { |r| r[:status] }.each_with_object({}) do |r, acc|
          acc[r[:status]] ||= r.slice(:provider_code, :internal_code, :action)
        end
        { error_map: map }
      end

      def base_url(provider)
        servers = @spec.servers
        sandbox = find_server(servers, SANDBOX)
        default = sandbox || servers.first
        production = find_server(servers, PRODUCTION) || (servers - [sandbox]).first || default
        { default: default&.url, production: production&.url, env_var: "#{provider[:env_prefix]}_BASE_URL" }
      end

      def find_server(servers, pattern) = servers.find { |s| pattern.match?("#{s.url} #{s.description}") }

      def override(key) = @overrides.to_h.fetch(key, {}).transform_keys(&:to_sym)

      def provider_naming
        name = override('provider')[:name] || @provider_name
        naming = name ? Naming.from_provider(name) : Naming.from_title(@spec.title)
        naming.merge(override('provider').slice(:class_name))
      end

      def operation(role, endpoint)
        own = rows.select { |r| r[:role] == role }
        statuses = value(:statuses)
        OperationPlan.new(role: role, method: endpoint.method, path: endpoint.path,
                          path_params: endpoint.path.scan(/\{(\w+)\}/).flatten,
                          headers: role == :create ? value(:fields)[:headers] : [], body_encoding: 'json',
                          success_statuses: success_statuses(endpoint, own),
                          response_id_path: statuses[:response_id_path],
                          response_status_path: statuses[:response_status_path],
                          error_statuses: own.reject { |r| r[:action] == 'treat_as_success' }.map { |r| r[:status] })
      end

      def success_statuses(endpoint, own)
        ok = endpoint.responses.map { |r| r.status.to_i }.grep(200..299)
        (ok + own.select { |r| r[:action] == 'treat_as_success' }.map { |r| r[:status] }).uniq.sort
      end

      def gateway_config
        currency = value(:amount)[:currencies].first || 'RUB'
        value(:fields)[:requisite_types].map do |type|
          { external_method: "#{type}_payout", gateway: "#{currency}_#{type.upcase}_WITHDRAW" }
        end
      end

      def outside_contract
        named = HELPERS.filter_map { |role, helper| roles[role] && { endpoint: roles[role], helper: helper } }
        named + roles[:other].map { |ep| { endpoint: ep, helper: nil } }
      end

      def meta
        { spec_title: @spec.title, spec_version: @spec.version, spec_file: @spec.source_path,
          forge_version: Forge::VERSION }
      end
    end
  end
end
