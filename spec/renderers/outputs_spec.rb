# frozen_string_literal: true

require 'fileutils'

RSpec.describe Forge::Renderers do
  let(:plan) { plan_for('examples/specs/novapay.yaml') }

  def generate(plan, dir)
    FileUtils.rm_rf(dir)
    Forge::Renderers::Runner.render(plan, out_dir: dir)
    dir
  end

  describe Forge::Renderers::IntegrationDoc do
    subject(:doc) { described_class.new(plan).render }

    it 'contains every heading and table row of the reference guide' do
      reference = File.read('spec/reference/novapay/INTEGRATION.md')
      reference.lines.map(&:strip).select { |l| l.start_with?('#', '|', '-', '{', 'HMAC') }.each do |line|
        expect(doc).to include(line), "missing: #{line}"
      end
    end

    it 'has the assumptions section with 3 WARN rows and lists INFO-free' do
      section = doc[/## Допущения.*?## Проверка/m]
      expect(section.scan('| WARN |').size).to eq(3)
      expect(section.scan('| INFO |').size).to eq(0)
      expect(doc).to include('## Поля запроса', '## Вне контракта', '`credentials.api_key`',
                             '`credentials.callback_secret`')
    end
  end

  describe Forge::Renderers::Fixtures do
    it 'is a superset of the reference fixtures' do
      ours = JSON.parse(described_class.new(plan).render)
      expect(ours).to deep_include(JSON.parse(File.read('spec/reference/novapay/fixtures.json')))
      expect(ours['fetch_status']).to include('response_200' => hash_including('status' => 'completed'),
                                              'expected_operation_status' => 'approved')
    end

    it 'injects the known status only where the response schema has the status path (balance, wrapped cancel)' do
      ours = JSON.parse(described_class.new(plan).render)
      expect(ours.dig('balance', 'response_200')).not_to have_key('status')
      wrapped = JSON.parse(described_class.new(plan_for_hash(wrapped_cancel_spec)).render)
      expect(wrapped.dig('cancel', 'response_200')).to include('invoice' => hash_including('status' => 'pending'))
      expect(wrapped.dig('cancel', 'response_200')).not_to have_key('status')
    end

    # Статус живёт в Invoice; cancel отвечает обёрткой {message, invoice} — статуса на верхнем уровне нет.
    def wrapped_cancel_spec
      id = { 'name' => 'id', 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }
      invoice = { '$ref' => '#/components/schemas/Invoice' }
      json = ->(schema) { { 'description' => 'ok', 'content' => { 'application/json' => { 'schema' => schema } } } }
      create = { 'operationId' => 'createPayout', 'requestBody' => body_json({ 'amount' => { 'type' => 'integer' } }),
                 'responses' => { '201' => json.call(invoice) } }
      status = { 'operationId' => 'getPayout', 'parameters' => [id], 'responses' => { '200' => json.call(invoice) } }
      cancel = { 'operationId' => 'cancelPayout', 'parameters' => [id],
                 'responses' => { '200' => json.call({ 'type' => 'object', 'properties' => {
                                                       'message' => { 'type' => 'string' }, 'invoice' => invoice
                                                     } }) } }
      schema = { 'type' => 'object', 'properties' => { 'id' => { 'type' => 'string' },
                                                       'status' => { 'type' => 'string',
                                                                     'enum' => %w[pending paid] } } }
      build_spec(paths: { '/payouts' => { 'post' => create }, '/payouts/{id}' => { 'get' => status },
                          '/payouts/{id}/cancel' => { 'post' => cancel } }, schemas: { 'Invoice' => schema })
    end
  end

  describe Forge::Renderers::ServiceSpec do
    it 'generates a green spec for novapay with 11+ examples' do
      dir = generate(plan, 'tmp/out_spec/novapay')
      out = Forge::Verifier.spec!("#{dir}/novapay_service_spec.rb", load_paths: ['lib', dir])
      expect(out).to match(/(\d+) examples, 0 failures/)
      expect(out[/(\d+) examples/, 1].to_i).to be >= 11
    end

    it 'generates green specs for cardpay and swiftpay (timestamped signature verified)' do
      %w[cardpay.yaml swiftpay.json].each do |file|
        name = file.split('.').first
        dir = generate(plan_for("examples/specs/#{file}"), "tmp/out_spec/#{name}")
        out = Forge::Verifier.spec!("#{dir}/#{name}_service_spec.rb", load_paths: ['lib', dir])
        expect(out).to include('examples, 0 failures'), out
      end
    end

    it 'generates a green spec for an oauth2 client_credentials provider (token stubbed, requested once)' do
      dir = generate(plan_for('spec/fixtures/oauth2_payout.yaml'), 'tmp/out_spec/oauthpay')
      out = Forge::Verifier.spec!("#{dir}/oauthpay_service_spec.rb", load_paths: ['lib', dir])
      expect(out).to include('examples, 0 failures'), out
      service = File.read("#{dir}/oauthpay_service.rb")
      expect(service).to include("TOKEN_URL = ENV.fetch('OAUTHPAY_TOKEN_URL', \"\#{BASE_URL}/oauth/token\")",
                                 'def access_token', "form: { 'grant_type' => 'client_credentials' }")
    end

    it 'renders callbacks_not_supported for a plan without webhook' do
      schemes = { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } }
      body = body_json({ 'amount' => { 'type' => 'integer' }, 'currency' => { 'type' => 'string' } })
      responses = response_json(201, { 'id' => { 'type' => 'string' },
                                       'status' => { 'type' => 'string', 'enum' => %w[pending] } })
      spec = build_spec(security_schemes: schemes, security: [{ 'b' => [] }],
                        paths: { '/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                             'requestBody' => body, 'responses' => responses } } })
      code = described_class.new(plan_for_hash(spec)).render
      expect(code).to include('returns callbacks_not_supported', 'status_endpoint_missing')
    end
  end
end
