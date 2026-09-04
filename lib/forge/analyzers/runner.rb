# frozen_string_literal: true

require_relative 'endpoint_roles'
require_relative 'auth'
require_relative 'statuses'
require_relative 'errors'
require_relative 'webhooks'
require_relative 'amount'
require_relative 'fields'

module Forge
  module Analyzers
    # Фиксированный порядок анализаторов; спековые проверки (servers, эндпоинты вне контракта).
    class Runner
      ORDER = [EndpointRoles, Auth, Statuses, Errors, Webhooks, Amount, Fields].freeze

      def self.run(spec, rules:, include_paths: [], overrides: nil) = new(spec, rules, include_paths, overrides).run

      def initialize(spec, rules, include_paths, overrides)
        @spec = spec
        @rules = rules
        @overrides = overrides || {}
        @include_paths = include_paths + Array(@overrides.dig('paths', 'include'))
      end

      # Overrides: endpoints — сразу после ролей (остальные анализаторы зависят от них), прочее — в конце.
      def run
        findings = ORDER.each_with_object({}) do |klass, acc|
          finding = klass.new(@spec, @rules, include_paths: @include_paths, findings: acc).call
          finding = Plan::OverridesApply.roles(finding, @overrides, @spec) if finding.key == :endpoint_roles
          acc[finding.key] = finding
        end
        findings[:endpoint_roles] = with_spec_warnings(findings[:endpoint_roles])
        Plan::OverridesApply.findings(findings, @overrides, @spec)
      end

      private

      def with_spec_warnings(roles)
        extra = production_default + outside_contract(roles.value) + no_cancel(roles.value)
        roles.with(warnings: roles.warnings + extra)
      end

      def production_default
        servers = @spec.servers
        return [] if servers.empty? || servers.first.then do |s|
          "#{s.url} #{s.description}".match?(/sandbox|test|staging|dev/i)
        end

        [Warning.new(level: :warn, code: :production_default,
                     message: "no sandbox server; default BASE_URL is production (#{servers.first.url})",
                     pointer: '#/servers/0', hint: 'base_url.default: <sandbox url>  (overrides.yml)')]
      end

      def outside_contract(value)
        helpers = { cancel: 'cancel_request', balance: 'fetch_balance' }
        named = helpers.filter_map { |role, helper| value[role] && [value[role], "generated as `#{helper}` helper"] }
        others = value[:other].map { |ep| [ep, 'not used'] }
        (named + others).map do |ep, note|
          Warning.new(level: :info, code: :outside_contract, pointer: ep.pointer, hint: nil,
                      message: "#{ep.method.upcase} #{ep.path} (#{ep.operation_id}) — #{note}")
        end
      end

      def no_cancel(value)
        return [] if value[:cancel]

        [Warning.new(level: :info, code: :no_cancel_endpoint, pointer: nil, hint: nil,
                     message: 'no cancel endpoint; cancel_request not generated')]
      end
    end
  end
end
