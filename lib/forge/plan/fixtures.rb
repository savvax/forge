# frozen_string_literal: true

require 'base64'
require_relative '../fixtures/synthesizer'
require_relative 'fixtures_operation'
require_relative '../fixtures/validator'

module Forge
  module Plan
    # fixtures.json из examples спеки; недостающее синтезируется по схемам (docs/OUTPUT_FORMAT.md § 4).
    class Fixtures
      Synth = Forge::Fixtures::Synthesizer
      Validator = Forge::Fixtures::Validator
      CALLBACK_KEYS = { 'approved' => 'callback', 'rejected' => 'callback_failed',
                        'in_progress' => 'callback_processing' }.freeze

      def initialize(spec, findings, plan_parts)
        @spec = spec
        @f = findings
        @p = plan_parts
      end

      attr_reader :mismatches

      def build
        @mismatches = []
        fixtures = { 'meta' => meta, 'auth' => auth, 'create_request' => create }
        fixtures['fetch_status'] = status_fixture if role(:status)
        fixtures.merge!(callbacks)
        fixtures['cancel'] = operation_fixture(:cancel) if role(:cancel)
        fixtures['balance'] = operation_fixture(:balance) if role(:balance)
        validate!(fixtures)
        fixtures
      end

      # Примеры из спеки сверяются с её же схемами: расхождение → INFO fixture_schema_mismatch (в Builder).
      def validate!(fixtures)
        @mismatches += Validator.check(fixtures.dig('create_request', 'request'), role(:create).request_body&.schema,
                                       'create_request.request')
        role(:create).responses.each { |res| @mismatches += response_mismatches(fixtures, res) }
        schema = @f[:webhooks].value[:endpoint]&.request_body&.schema
        %w[callback callback_failed callback_processing].each do |key|
          @mismatches += Validator.check(fixtures.dig(key, 'payload'), schema, "#{key}.payload")
        end
      end

      def response_mismatches(fixtures, res)
        example = fixtures.dig('create_request', "response_#{res.status}")
        example = example['body'] if example.is_a?(Hash) && example.key?('body') && example.key?('headers')
        Validator.check(example, res.schema, "create_request.response_#{res.status}")
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
        fixture = create_request(ep).merge(responses(ep))
        synthesize_success(fixture, ep)
        remember_create_success(ep, fixture)
        fixture['expected_operation_status'] = expected_status(success_of(fixture), 'in_progress')
        fixture.compact
      end

      def create_request(endpoint)
        body = endpoint.request_body
        example = body&.examples.to_h.values.first
        request = example || Synth.example(body&.schema, 'request')
        operation, extras = request && FixturesOperation.new(@f).from(request)
        base = { 'endpoint' => label(endpoint), 'request' => request, 'operation' => operation }
        base['synthesized'] = true if example.nil? && request
        base.merge(extras.to_h)
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
        hash
      end

      # Успешный ответ без примера: та же схема, что у create → его пример; иначе синтез по схеме.
      def synthesize_success(fixture, endpoint, base: nil)
        res = endpoint.responses.find { |r| r.status.start_with?('2') }
        return if res.nil? || fixture.key?("response_#{res.status}")

        # 2xx без схемы (201 + Location у Velo/Dwolla) → {}: сервис читает body['id'], nil сломал бы spec.
        example = res.schema ? success_example(res.schema, base) : {}
        fixture["response_#{res.status}"] = Marshal.load(Marshal.dump(example))
      end

      def success_example(schema, base)
        same = base && schema.ref_name && base[:ref] == schema.ref_name
        example = same ? base[:example] : Synth.example(schema, 'response')
        with_known_status(example)
      end

      # Синтез даёт 'status_example'; подставляем первый статус провайдера из карты, чтобы сервис его распознал.
      def with_known_status(example)
        path = @f[:statuses].value[:response_status_path]
        raw = @p[:status_map].keys.first
        return example unless raw && path && !path.empty? && example.is_a?(Hash)

        return example unless placeholder?(dig(example, path))

        set_path(Marshal.load(Marshal.dump(example)), path, raw)
      end

      def placeholder?(value) = value.nil? || (value.is_a?(String) && value.end_with?('_example'))

      def responses(endpoint)
        endpoint.responses.each_with_object({}) do |res, acc|
          example = res.examples.values.first
          # Глубокая копия: пример из $ref — один объект для create и status; set_path в status_fixture менял бы оба.
          acc["response_#{res.status}"] = with_headers(res, Marshal.load(Marshal.dump(example))) if example
        end
      end

      def with_headers(res, example)
        header = res.headers.keys.find { |h| h == @f[:errors].value[:retry_after_header] }
        return example unless header

        { 'headers' => { header => res.headers[header].example || 60 }, 'body' => example }
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
