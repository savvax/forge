# frozen_string_literal: true

module Forge
  module Renderers
    # URL-ы операций и dig-выражения по схемам ответов (id, статус, код ошибки, баланс).
    class ServicePaths
      ERROR_CODE_PATHS = [%w[error code], %w[code], ['errors', 0, 'code'], %w[error_code]].freeze

      def initialize(plan)
        @plan = plan
      end

      def op(role) = @plan.operations[role]

      ID_EXPR = '#{operation.provider_operation_id}' # rubocop:disable Lint/InterpolationCheck

      def url(role)
        path = op(role).path.gsub(/\{\w+\}/, ID_EXPR)
        "\"\#{BASE_URL}#{path}\""
      end

      def dig(path)
        return "['#{path.first}']" if path.size == 1

        ".dig(#{path.map { |p| p.is_a?(Integer) ? p : "'#{p}'" }.join(', ')})"
      end

      def body(path) = "response.body#{dig(path)}"
      def payload(path) = "payload#{dig(path)}"
      def create_error_code = body(error_code_path)
      def create_error_message = body(error_code_path[0..-2] + ['message'])

      def error_code_path
        @error_code_path ||= begin
          schema = op(:create).endpoint.responses.find { |r| r.status.to_i >= 400 && r.schema }&.schema
          ERROR_CODE_PATHS.find { |p| has?(schema, p) } || %w[error code]
        end
      end

      def callback_error_code
        webhook = @plan.webhook
        schema = webhook[:endpoint].request_body&.schema
        wrapper = webhook[:status_field].to_a[0..-2]
        path = [%w[error code], wrapper + %w[error code], wrapper + %w[reason code]].find { |p| has?(schema, p) }
        path && ", #{payload(path)}"
      end

      def balance_keys
        schema = success_schema(:balance)
        (schema&.properties || {}).keys
      end

      def cancel_client_call
        verb = op(:cancel).method == 'delete' ? 'delete' : 'post'
        "client.#{verb}(#{url(:cancel)}, headers: auth_headers)"
      end

      def cancel_has_status? = has?(success_schema(:cancel), op(:cancel).response_status_path)

      private

      def success_schema(role) = op(role).endpoint.responses.find { |r| r.status.start_with?('2') }&.schema

      def has?(schema, path)
        return false if schema.nil? || path.nil? || path.empty?

        !path.reduce(schema) { |node, key| node && child(node, key) }.nil?
      end

      def child(node, key) = key.is_a?(Integer) ? node.items : node.properties&.[](key)
    end
  end
end
