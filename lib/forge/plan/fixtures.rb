# frozen_string_literal: true

require 'base64'

module Forge
  module Plan
    # fixtures.json из examples спеки (docs/OUTPUT_FORMAT.md § 4). Недостающее досинтезирует T11.
    class Fixtures
      REQUISITE_EXPR = /payout_requisite\.dig\((.+?), '(.+?)'\)/
      CALLBACK_KEYS = { 'approved' => 'callback', 'rejected' => 'callback_failed',
                        'in_progress' => 'callback_processing' }.freeze

      def initialize(spec, findings, plan_parts)
        @spec = spec
        @f = findings
        @p = plan_parts
      end

      def build
        fixtures = { 'meta' => meta, 'auth' => auth, 'create_request' => create }
        fixtures['fetch_status'] = operation_fixture(:status, expected: 'approved') if role(:status)
        fixtures.merge!(callbacks)
        fixtures['cancel'] = operation_fixture(:cancel) if role(:cancel)
        fixtures['balance'] = operation_fixture(:balance) if role(:balance)
        fixtures
      end

      private

      def role(name) = @f[:endpoint_roles].value[name]

      def meta
        { 'provider' => @p[:provider][:name], 'spec' => "#{@spec.title} #{@spec.version}", 'forge' => Forge::VERSION }
      end

      def auth
        a = @f[:auth].value
        header = case a[:type]
                 when 'api_key' then a[:header] && { a[:header] => '<credentials.api_key>' }
                 when 'bearer' then { 'Authorization' => 'Bearer <credentials.token>' }
                 when 'basic' then { 'Authorization' => "Basic #{Base64.strict_encode64('<login>:<password>')}" }
                 end
        { 'headers' => header || {} }
      end

      def create
        ep = role(:create)
        request = ep.request_body&.examples.to_h.values.first
        fixture = { 'endpoint' => label(ep), 'request' => request, 'operation' => request && operation_from(request) }
        fixture.merge!(responses(ep))
        fixture['expected_operation_status'] =
          expected_status(fixture['response_201'] || fixture['response_200'], 'in_progress')
        fixture.compact
      end

      def operation_fixture(name, expected: nil)
        ep = role(name)
        fixture = { 'endpoint' => label(ep) }.merge(responses(ep))
        fixture['expected_operation_status'] = expected if expected && fixture['response_200']
        fixture
      end

      def responses(endpoint)
        endpoint.responses.each_with_object({}) do |res, acc|
          example = res.examples.values.first
          next unless example

          acc["response_#{res.status}"] = with_headers(res, example)
        end
      end

      def with_headers(res, example)
        header = res.headers.keys.find { |h| h == @f[:errors].value[:retry_after_header] }
        return example unless header

        { 'headers' => { header => res.headers[header].example || 60 }, 'body' => example }
      end

      def label(endpoint) = "#{endpoint.method.upcase} #{endpoint.path}"

      # Обратное отображение примера запроса в Provider::Operation по FieldMapping.
      def operation_from(request)
        op = { 'id' => nil, 'amount' => nil, 'currency' => nil, 'payout_requisite' => {} }
        type = request_type(request)
        @f[:fields].value[:request].each do |m|
          value = m.path.reduce(request) { |node, key| node.is_a?(Hash) ? node[key] : nil }
          next if value.nil?

          assign(op, m, value, type)
        end
        op.compact
      end

      def request_type(request)
        m = @f[:fields].value[:request].find { |x| x.source_expr == 'requisite_type' }
        m&.path&.reduce(request) { |node, key| node.is_a?(Hash) ? node[key] : nil }
      end

      def assign(operation, mapping, value, type)
        case mapping.source_expr
        when 'operation.id.to_s' then operation['id'] = value.to_s
        when 'operation.currency' then operation['currency'] = value.to_s
        when REQUISITE_EXPR then assign_requisite(operation, type, value, ::Regexp.last_match)
        else operation['amount'] = major_amount(value) if mapping.transform == 'amount'
        end
      end

      def assign_requisite(operation, type, value, match)
        key = match[1].delete("'")
        key = type if key == 'requisite_type'
        (operation['payout_requisite'][key] ||= {})[match[2]] = value if key
      end

      def major_amount(value)
        amount = @f[:amount].value
        number = amount[:unit] == :minor ? value.to_r / amount[:multiplier] : value.to_r
        format('%.2f', number)
      end

      def expected_status(response, default)
        path = @f[:statuses].value[:response_status_path]
        raw = response && path.reduce(response) { |node, key| node.is_a?(Hash) ? node[key] : nil }
        @p[:status_map][raw.to_s] || default
      end

      def callbacks
        w = @f[:webhooks].value
        return {} unless w[:endpoint]

        w[:endpoint].request_body&.examples.to_h.each_with_object({}) do |(_name, payload), acc|
          status = callback_status(payload, w)
          key = CALLBACK_KEYS[status]
          next if key.nil? || acc.key?(key)

          acc[key] =
            { 'headers' => signature_header(w), 'payload' => payload, 'expected_operation_status' => status }.compact
        end
      end

      def callback_status(payload, webhook)
        event = webhook[:event_field] && payload[webhook[:event_field]]
        by_event = event && @p[:event_map][event.to_s]
        return by_event if by_event

        raw = webhook[:status_field]&.reduce(payload) { |node, key| node.is_a?(Hash) ? node[key] : nil }
        @p[:status_map][raw.to_s]
      end

      def signature_header(webhook)
        sig = webhook[:signature]
        return nil unless sig[:header]

        algorithm = sig[:algorithm].to_s.upcase
        { sig[:header] => "<HMAC-#{algorithm}(#{sig[:payload]}, #{sig[:secret_key]}) #{sig[:encoding]}>" }
      end
    end
  end
end
