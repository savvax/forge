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

      ID_EXPR = '#{operation.provider_operation_key}' # rubocop:disable Lint/InterpolationCheck

      # {param}: id выплаты (последний у status/cancel) → provider_operation_key, остальные → credentials.<param>.
      def url(role)
        own = role == :create ? nil : op(role).path.scan(/\{(\w+)\}/).flatten.last
        path = op(role).path.gsub(/\{(\w+)\}/) do |m|
          m[1..-2] == own ? ID_EXPR : "\#{credentials.fetch('#{m[1..-2]}')}"
        end
        literal = "\"\#{BASE_URL}#{path}\""
        query_api_key? ? "with_auth(#{literal})" : literal
      end

      def query_api_key? = @plan.auth[:type] == 'api_key' && @plan.auth[:location] == 'query'

      def dig(path)
        return "['#{path.first}']" if path.size == 1

        ".dig(#{path.map { |p| p.is_a?(Integer) ? p : "'#{p}'" }.join(', ')})"
      end

      def body(path) = "response.body#{dig(path)}"
      # Ответ статуса — массив: ['status'] на Array бросил бы TypeError; nil → unknown_provider_status.
      def status_body = success_schema(:status)&.type == 'array' ? 'nil' : body(op(:status).response_status_path)
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
        field = op(:cancel).status_request_field
        if field
          return "client.post(#{url(:cancel)}, json: { '#{field}' => operation.provider_operation_key }, " \
                 'headers: auth_headers)'
        end

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
