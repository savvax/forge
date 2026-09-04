# frozen_string_literal: true

require_relative 'overrides_edits'

module Forge
  module Plan
    # Применение overrides к findings: поле за полем, каждое → INFO override_applied, закрытые WARN снимаются.
    class OverridesApply
      ROLE_WARNINGS = %i[role_conflict low_confidence no_create_endpoint].freeze

      def self.roles(finding, overrides, spec) = new(overrides, spec).roles(finding)
      def self.findings(findings, overrides, spec) = new(overrides, spec).findings(findings)

      def initialize(overrides, spec)
        @o = overrides || {}
        @spec = spec
        @applied = []
        @closed = []
      end

      # endpoints.<operationId>: role — до остальных анализаторов (они зависят от ролей).
      def roles(finding)
        return finding if @o['endpoints'].to_h.empty?

        value = finding.value.dup
        @o['endpoints'].each { |op_id, role| reassign(value, op_id, role.to_s) }
        value[:other] = @spec.endpoints - value.slice(*Analyzers::EndpointRoles::ROLES).values.compact
        finding.with(value: value, warnings: finding.warnings.reject { |w| ROLE_WARNINGS.include?(w.code) } + @applied)
      end

      def findings(findings)
        edits = OverridesEdits.new(@o, self)
        result = findings.dup
        %i[statuses webhooks amount fields auth errors].each { |key| result[key] = edits.public_send(key, result) }
        close(:production_default, nil) && applied('base_url', @o['base_url'].keys.join(', ')) if @o.dig('base_url',
                                                                                                         'default')
        finish(result)
      end

      def applied(key, value)
        @applied << Warning.new(level: :info, code: :override_applied, message: "#{key} → #{value}", pointer: nil,
                                hint: nil)
      end

      def close(code, fragment) = @closed << [code, fragment]

      private

      def reassign(value, op_id, role)
        endpoint = (@spec.endpoints + @spec.webhooks).find { |e| e.operation_id == op_id }
        unless endpoint
          raise SpecError.new("endpoints.#{op_id}: no such operationId in the spec",
                              hint: 'overrides cannot add endpoints')
        end

        value.each { |k, v| value[k] = nil if v.equal?(endpoint) }
        return applied("endpoints.#{op_id}", role) if role == 'other'

        value[role.to_sym] = endpoint
        value[:confidences] = value[:confidences].merge(role.to_sym => 1.0)
        applied("endpoints.#{op_id}", role)
      end

      def closed?(warning)
        @closed.any? { |code, frag| warning.code == code && (frag.nil? || warning.message.include?(frag)) }
      end

      def finish(findings)
        cleaned = findings.transform_values { |f| f.with(warnings: f.warnings.reject { |w| closed?(w) }) }
        roles = cleaned[:endpoint_roles]
        cleaned.merge(endpoint_roles: roles.with(warnings: roles.warnings + @applied))
      end
    end
  end
end
