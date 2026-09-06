# frozen_string_literal: true

# rake fuzz:mock — враждебные запросы к сгенерированным мок-серверам (все спеки из examples/, in-process).
# Красный: исключение или ответ 5xx. Мок — часть демо: чужой клиент не должен его ронять.
require 'rack/mock'
require 'json'
require_relative 'harness'
require_relative '../../lib/forge'
require_relative '../../lib/forge/generate_command'

module Fuzz
  class Mock
    BODIES = ['', 'not json', '[]', '"str"', '5', 'null', '{}', '{"amount": {}}', '{"amount": []}', '{"amount": "abc"}',
              '{"amount": null}', '{"amount": -1}', '{"amount": 1e400}', '{"amount": 99999999999999999999999999}',
              '{"amount": 100, "currency": 5, "recipient": "x", "type": [], "bank_code": {}}', '{"amount": true}',
              '{"amount": {"value": 100}}', "{\"amount\": \"\xff\"}".b, '{"payout_id": 5}', '{"payout_id": {"a": 1}}',
              '{"id": []}', "{\"#{'a' * 100_000}\": 1}", '{"amount": 100, "amount": 200}',
              "{\"a\": #{'[' * 200}#{']' * 200}}"].freeze
    PATHS = ['/payouts', '/payouts/', '/payouts/x', '/payouts/%00', '/payouts/../../etc', "/payouts/#{'a' * 5000}",
             '/payouts/x/cancel', '/payouts/status', '/balance', '/_simulate/x/y', '/_simulate/%00/%00',
             "/_simulate/x/#{'e' * 3000}", '/_state', '/', '/nope'].freeze
    AUTH = { 'HTTP_X_API_KEY' => 'test-key', 'HTTP_AUTHORIZATION' => 'Bearer test-key' }.freeze
    HEADERS = [{}, AUTH, AUTH.merge('HTTP_IDEMPOTENCY_KEY' => 'k'), AUTH.merge('HTTP_IDEMPOTENCY_KEY' => 'k' * 10_000),
               AUTH.merge('CONTENT_TYPE' => 'text/plain'), AUTH.merge('HTTP_X_API_KEY' => "\xff".b)].freeze
    EVENTS = ['completed', 'nope', '', '%00', 'payout.completed', 'e' * 3000].freeze
    CREATE = '{"amount": 100, "currency": "RUB", "recipient": {"phone": "+7"}, "type": "sbp", "bank_code": "1"}'

    def initialize
      @h = Harness.new('mock')
      @work = @h.workdir('mock')
    end

    def run
      Dir['examples/specs/*'].each do |spec|
        name = File.basename(spec, '.*')
        app = build(name, spec)
        next unless app

        client = Rack::MockRequest.new(app)
        PATHS.product(%w[GET POST PUT DELETE]).each do |path, m|
          @h.check("#{name} #{m} #{path[0, 30]}") { hit(client, m, path) }
        end
        @h.check("#{name} simulate") { simulate(client) }
      end
      @h.report!
    end

    private

    def build(name, spec)
      out = File.join(@work, name)
      opts = { spec: spec, out: out, force: true, verify: false, format: 'json', include_paths: [], overrides: nil,
               provider: nil, templates_dir: nil }
      $stdout = StringIO.new
      Forge::GenerateCommand.new(opts).run
      load File.join(out, 'mock_server.rb')
      Object.const_get("#{name.capitalize}Mock").tap { |app| app.set :raise_errors, true }
    rescue Forge::Error
      nil
    ensure
      $stdout = STDOUT
    end

    def hit(client, method, path)
      BODIES.product(HEADERS).each do |body, headers|
        res = client.request(method, path, headers.merge(input: body))
        raise "#{method} #{path[0, 40]} body=#{body[0, 40].inspect}: HTTP #{res.status}" if res.status >= 500
      end
    end

    # У провайдеров с другим путём create выплаты нет — тогда simulate бьёт по несуществующему id.
    def simulate(client)
      created = JSON.parse(client.post('/payouts', AUTH.merge(input: CREATE)).body)
      id = (created.is_a?(Hash) && (created['id'] || created.dig('payout', 'id'))) || 'x'
      EVENTS.each do |event|
        res = client.post("/_simulate/#{id}/#{event}", {})
        raise "simulate #{event[0, 20]}: HTTP #{res.status}" if res.status >= 500
      end
    rescue JSON::ParserError
      nil # create вернул не JSON (404 HTML): нечего симулировать
    end
  end
end

Fuzz::Mock.new.run if $PROGRAM_NAME == __FILE__
