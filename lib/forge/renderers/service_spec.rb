# frozen_string_literal: true

require_relative 'base'
require_relative 'service_paths'

module Forge
  module Renderers
    # <provider>_service_spec.rb по templates/service_spec.rb.erb (docs/OUTPUT_FORMAT.md § 2).
    class ServiceSpec < Base
      ID_EXPR = '#{provider_id}' # rubocop:disable Lint/InterpolationCheck

      def template_name = 'service_spec.rb.erb'
      def filename = "#{plan.provider[:name]}_service_spec.rb"

      private

      def paths = @paths ||= ServicePaths.new(plan)
      def fx = plan.fixtures
      def op(role) = plan.operations[role]
      def class_name = plan.provider[:class_name]
      def signature = plan.webhook&.dig(:signature)
      def signature? = !signature&.dig(:header).nil?
      def timestamp_unsupported? = plan.warnings.any? { |w| w.code == :signature_with_timestamp }
      def dig(node, path) = path.to_a.reduce(node) { |cur, key| cur.is_a?(Hash) ? cur[key] : nil }

      def auth_header_expectation
        case plan.auth[:type]
        when 'api_key' then plan.auth[:header] && "'#{plan.auth[:header]}' => 'test_api_key'"
        when 'bearer' then "'Authorization' => 'Bearer test_token'"
        when 'basic' then "'Authorization' => \"Basic \#{Base64.strict_encode64('test_login:test_password')}\""
        end
      end

      def url(role) = "\"\#{described_class::BASE_URL}#{op(role).path.gsub(/\{\w+\}/, ID_EXPR)}\""
      def create_response_status = op(:create).success_statuses.first
      def status_verb = op(:status).status_request_field ? 'post' : 'get'
      def create_response_key = "response_#{create_response_status}"
      def status_response_key = fx['fetch_status']&.keys&.find { |k| k.start_with?('response_2') }
      def provider_id_path = op(:create).response_id_path.inspect
      def error_code(status) = plan.error_map[status] && "provider.#{plan.error_map[status][:internal_code]}"
      def min? = plan.validations.any? { |v| v[:rule] == :min }

      def overridden_paths
        plan.warnings.filter_map { |w| w.code == :override_applied && w.message[/\Afields\.(\S+) → .*source/, 1] }
            .map { |path| path.split('.') }
      end

      def callback_id_path = (plan.webhook[:id_field] || ['id']).inspect
      def event_of(key) = fx.dig(key, 'payload', plan.webhook[:event_field].to_s)

      def sign_expr(body_var)
        "sign(#{body_var}, algorithm: '#{signature[:algorithm]}', encoding: '#{signature[:encoding]}')"
      end

      def callback_error_code
        code = paths.callback_error_code
        return nil unless code && fx['callback_failed']

        dig(fx.dig('callback_failed', 'payload'), code.scan(/'([^']+)'/).flatten)
      end

      def cancel_expected
        response = fx.dig('cancel', "response_#{op(:cancel).success_statuses.first}")
        plan.status_map[dig(response, op(:cancel).response_status_path).to_s]
      end
    end
  end
end
