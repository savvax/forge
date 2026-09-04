# frozen_string_literal: true

require 'base64'
require_relative '../fixtures/synthesizer'

module Forge
  module Plan
    # fixtures.json из examples спеки; недостающее синтезируется по схемам (docs/OUTPUT_FORMAT.md § 4).
    class Fixtures
      Synth = Forge::Fixtures::Synthesizer
      REQUISITE_EXPR = /\Aoperation\.payout_requisite\.dig\((.+?), '(.+?)'\)\z/
      CALLBACK_KEYS = { 'approved' => 'callback', 'rejected' => 'callback_failed',
                        'in_progress' => 'callback_processing' }.freeze

      def initialize(spec, findings, plan_parts)
        @spec = spec
        @f = findings
        @p = plan_parts
      end

      def build
        fixtures = { 'meta' => meta, 'auth' => auth, 'create_request' => create }
        fixtures['fetch_status'] = status_fixture if role(:status)
        fixtures.merge!(callbacks)
        fixtures['cancel'] = operation_fixture(:cancel) if role(:cancel)
        fixtures['balance'] = operation_fixture(:balance) if role(:balance)
        fixtures
      end

      private

      def role(name) = @f[:endpoint_roles].value[name]
      def label(endpoint) = "#{endpoint.method.upcase} #{endpoint.path}"
      def dig(node, path) = path.to_a.reduce(node) { |cur, key| cur.is_a?(Hash) ? cur[key] : nil }
      def success_of(fixture) = fixture.find { |k, _| k.start_with?('response_2') }&.last

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
        request = ep.request_body&.examples.to_h.values.first || Synth.example(ep.request_body&.schema, 'request')
        fixture = { 'endpoint' => label(ep), 'request' => request, 'operation' => request && operation_from(request) }
        fixture.merge!(@extras.to_h)
        fixture.merge!(responses(ep))
        synthesize_success(fixture, ep)
        remember_create_success(ep, fixture)
        fixture['expected_operation_status'] = expected_status(success_of(fixture), 'in_progress')
        fixture.compact
      end

      def remember_create_success(endpoint, fixture)
        ref = endpoint.responses.find { |r| r.status.start_with?('2') }&.schema&.ref_name
        @create_success = { ref: ref, example: success_of(fixture) }
      end

      def operation_fixture(name)
        ep = role(name)
        fixture = { 'endpoint' => label(ep) }.merge(responses(ep))
        synthesize_success(fixture, ep, base: @create_success)
        fixture
      end

      # Status-ответ: статус переставляется на первый approved, ожидание — approved.
      def status_fixture
        fixture = operation_fixture(:status)
        approved = @p[:status_map].find { |_raw, internal| internal == 'approved' }&.first
        response = success_of(fixture)
        path = @f[:statuses].value[:response_status_path]
        return fixture unless approved && response.is_a?(Hash) && path && !path.empty?

        set_path(response, path, approved)
        fixture.merge('expected_operation_status' => 'approved')
      end

      def set_path(hash, path, value)
        *head, last = path
        head.reduce(hash) { |node, key| node[key] ||= {} }[last] = value
      end

      # Успешный ответ без примера: та же схема, что у create → его пример; иначе синтез по схеме.
      def synthesize_success(fixture, endpoint, base: nil)
        res = endpoint.responses.find { |r| r.status.start_with?('2') }
        return if res&.schema.nil? || fixture.key?("response_#{res.status}")

        fixture["response_#{res.status}"] = Marshal.load(Marshal.dump(success_example(res.schema, base)))
      end

      def success_example(schema, base)
        same = base && schema.ref_name && base[:ref] == schema.ref_name
        same ? base[:example] : Synth.example(schema, 'response')
      end

      def responses(endpoint)
        endpoint.responses.each_with_object({}) do |res, acc|
          example = res.examples.values.first
          acc["response_#{res.status}"] = with_headers(res, example) if example
        end
      end

      def with_headers(res, example)
        header = res.headers.keys.find { |h| h == @f[:errors].value[:retry_after_header] }
        return example unless header

        { 'headers' => { header => res.headers[header].example || 60 }, 'body' => example }
      end

      # Обратное отображение примера запроса в Provider::Operation по FieldMapping.
      def operation_from(request)
        @extras = {}
        op = { 'id' => nil, 'amount' => nil, 'currency' => nil, 'payout_requisite' => {} }
        type = dig(request, @f[:fields].value[:request].find { |m| m.source_expr == 'requisite_type' }&.path)
        @f[:fields].value[:request].each do |m|
          value = dig(request, m.path)
          assign(op, m, value, type) unless value.nil?
        end
        fill_requisite_defaults(op['payout_requisite'])
        op.compact
      end

      # Канонические поля типа (CONTRACT § 3), которых нет в примере: чтобы override-выражения имели данные.
      def fill_requisite_defaults(requisites)
        defaults = Rules.load.fetch(:field_aliases)['requisite_defaults'].to_h
        requisites.each do |type, fields|
          defaults.fetch(type, {}).each { |key, value| fields[key] = value unless fields.key?(key) }
        end
      end

      def assign(operation, mapping, value, type)
        case mapping.source_expr
        when 'operation.id.to_s' then operation['id'] = value.to_s
        when 'operation.currency' then operation['currency'] = value.to_s
        when /\Aoperation\.description/ then operation['description'] = value.to_s
        when /\Aoperation\.customer&\.dig\('(\w+)'\)/ then (operation['customer'] ||= {})[::Regexp.last_match(1)] =
                                                             value
        when REQUISITE_EXPR then assign_requisite(operation, type, value, ::Regexp.last_match)
        else assign_extra(operation, mapping, value)
        end
      end

      # credentials.fetch('merchant_id') / callback_url — не часть Operation, кладутся рядом в create_request.
      def assign_extra(operation, mapping, value)
        case mapping.source_expr
        when /credentials\.fetch\('(\w+)'\)/ then (@extras['credentials'] ||= {})[::Regexp.last_match(1)] = value
        when 'callback_url' then @extras['config'] = { 'callback_url' => value }
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
        raw = dig(response, @f[:statuses].value[:response_status_path])
        @p[:status_map][raw.to_s] || default
      end

      def callbacks
        w = @f[:webhooks].value
        return {} unless w[:endpoint]

        payloads = w[:endpoint].request_body&.examples.to_h.values
        payloads = synthesized_callbacks(w) if payloads.empty?
        payloads.each_with_object({}) do |payload, acc|
          status = callback_status(payload, w)
          key = CALLBACK_KEYS[status]
          next if key.nil? || acc.key?(key)

          acc[key] = { 'headers' => signature_header(w), 'payload' => payload,
                       'expected_operation_status' => status }.compact
        end
      end

      # Нет примеров webhook: по одному payload на каждое событие (или статус) из карты.
      def synthesized_callbacks(webhook)
        schema = webhook[:endpoint].request_body&.schema
        return [] unless schema

        base = Synth.example(schema, 'payload')
        callback_variants(webhook).filter_map do |path, value|
          next unless path&.first

          Marshal.load(Marshal.dump(base)).tap { |payload| set_path(payload, path, value) }
        end
      end

      def callback_variants(webhook)
        by_event = @p[:event_map].keys.map { |event| [[webhook[:event_field]], event] }
        by_event.empty? ? @p[:status_map].keys.map { |raw| [webhook[:status_field], raw] } : by_event
      end

      def callback_status(payload, webhook)
        event = webhook[:event_field] && payload[webhook[:event_field]]
        by_event = event && @p[:event_map][event.to_s]
        by_event || @p[:status_map][dig(payload, webhook[:status_field]).to_s]
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
