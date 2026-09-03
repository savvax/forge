# frozen_string_literal: true

RSpec.describe Forge::IR::Builder do
  def build(file) = described_class.build(Forge::Loader.load(file), source_path: file)

  def endpoint(spec, method, path) = spec.endpoints.find { |e| e.method == method && e.path == path }

  context 'with novapay.yaml' do
    subject(:spec) { build('examples/specs/novapay.yaml') }

    let(:create) { endpoint(spec, 'post', '/payouts') }

    it 'has 5 endpoints, all from paths' do
      expect(spec.endpoints.size).to eq(5)
      expect(spec.endpoints.map(&:source).uniq).to eq([:paths])
    end

    it 'keeps title, servers and security schemes' do
      expect(spec.title).to eq('NovaPay Payout API')
      expect(spec.servers.map(&:url)).to eq(%w[https://api.sandbox.novapay.example/v1 https://api.novapay.example/v1])
      expect(spec.security_schemes.map(&:name)).to eq(['ApiKeyAuth'])
      expect(spec.security_schemes.first.location).to eq('header')
    end

    it 'resolves the Idempotency-Key parameter from $ref' do
      param = create.parameters.find { |p| p.name == 'Idempotency-Key' }
      expect(param.location).to eq('header')
      expect(param.required).to be(false)
      expect(param.schema.format).to eq('uuid')
    end

    it 'has 8 responses on create with json media type' do
      expect(create.responses.map(&:status)).to eq(%w[201 400 401 402 409 422 429 500])
      expect(create.responses.first.media_type).to eq('application/json')
    end

    it 'exposes schema constraints' do
      body = create.request_body
      expect(body.required).to be(true)
      expect(body.schema.ref_name).to eq('CreatePayoutRequest')
      expect(body.schema.properties['amount'].minimum).to eq(100_000)
      expect(body.schema.properties['recipient'].properties['phone'].pattern).to eq('^7\d{10}$')
      expect(body.schema.required).to eq(%w[amount currency external_id recipient])
    end

    it 'merges examples into one hash' do
      expect(create.request_body.examples.keys).to include('sbp_payout')
      expect(create.responses.first.examples.values.first).to include('id', 'status')
    end

    it 'keeps the create security and empty webhook security' do
      expect(create.security).to eq([{ 'ApiKeyAuth' => [] }])
      expect(endpoint(spec, 'post', '/webhooks/payout').security).to eq([])
      expect(create.pointer).to eq('#/paths/~1payouts/post')
    end

    it 'keeps response headers' do
      rate = create.responses.find { |r| r.status == '429' }
      expect(rate.headers.keys).to eq(['Retry-After'])
      expect(rate.headers['Retry-After'].type).to eq('integer')
    end

    it 'collects component schemas' do
      expect(spec.schemas['Recipient'].required).to eq(%w[type phone])
    end
  end

  context 'with cardpay.yaml' do
    subject(:spec) { build('examples/specs/cardpay.yaml') }

    it 'has 3 path endpoints and one callback endpoint' do
      expect(spec.endpoints.size).to eq(3)
      expect(spec.webhooks.size).to eq(1)
    end

    it 'turns callbacks into an Endpoint with source :callbacks' do
      cb = spec.webhooks.first
      expect(cb.source).to eq(:callbacks)
      expect(cb.parameters.map(&:name)).to eq(['X-Signature'])
      expect(cb.request_body.schema.ref_name).to eq('Notification')
    end

    it 'inherits root security' do
      expect(spec.default_security).to eq([{ 'bearerAuth' => [] }])
      expect(spec.endpoints.map(&:security).uniq).to eq([[{ 'bearerAuth' => [] }]])
    end
  end

  context 'with swiftpay.json (OpenAPI 3.1)' do
    subject(:spec) { build('examples/specs/swiftpay.json') }

    let(:body) { endpoint(spec, 'post', '/v1/payments/outbound').request_body.schema }

    it 'has 4 endpoints including DELETE and one top-level webhook' do
      expect(spec.endpoints.size).to eq(4)
      expect(spec.endpoints.map(&:method)).to include('delete')
      expect(spec.webhooks.size).to eq(1)
      expect(spec.webhooks.first.source).to eq(:webhooks)
    end

    it 'merges allOf into one object schema' do
      expect(body.properties.keys).to include('reference', 'amount', 'beneficiary', 'purpose')
      expect(body.required).to include('beneficiary', 'reference')
      expect(body.all_of).to be_nil
    end

    it 'turns 3.1 type arrays into nullable' do
      expect(body.properties['purpose'].type).to eq('string')
      expect(body.properties['purpose'].nullable).to be(true)
    end

    it 'keeps oneOf as is' do
      expect(body.properties['beneficiary'].one_of.size).to eq(2)
      expect(body.properties['beneficiary'].one_of.map(&:ref_name)).to eq(%w[IbanBeneficiary AccountBeneficiary])
    end

    it 'picks application/problem+json for 422' do
      res = endpoint(spec, 'post', '/v1/payments/outbound').responses.find { |r| r.status == '422' }
      expect(res.media_type).to eq('application/problem+json')
      expect(res.schema.ref_name).to eq('Problem')
    end
  end

  context 'with literal hashes' do
    it 'merges path-level parameters and prefers json among media types' do
      spec = build_spec(paths: { '/p/{id}' => {
                          'parameters' => [{ 'name' => 'id', 'in' => 'path', 'required' => true,
                                             'schema' => { 'type' => 'string' } }],
                          'get' => { 'responses' => { '200' => { 'description' => 'ok', 'content' => {
                            'text/plain' => { 'schema' => { 'type' => 'string' } },
                            'application/vnd+json' => { 'schema' => { 'type' => 'object' } }
                          } } } }
                        } })
      ep = ir_for(spec).endpoints.first
      expect(ep.parameters.map(&:name)).to eq(['id'])
      expect(ep.responses.first.media_type).to eq('application/vnd+json')
      expect(ep.responses.first.schema.type).to eq('object')
    end

    it 'keeps unresolved refs, multiple_of, items and any_of' do
      spec = build_spec(paths: { '/a' => { 'post' => {
                          'requestBody' => body_json({ 'x' => { 'x-forge-unresolved' => 'o.yaml#/X' },
                                                       'n' => { 'type' => 'number', 'multipleOf' => 0.01 },
                                                       'l' => { 'type' => 'array', 'items' => { 'type' => 'integer' } },
                                                       'v' => { 'anyOf' => [{ 'type' => 'string' },
                                                                            { 'type' => 'integer' }] } },
                                                     required: %w[x]),
                          'responses' => { '204' => { 'description' => 'none' } }
                        } } })
      props = ir_for(spec).endpoints.first.request_body.schema.properties
      expect(props['x'].unresolved_ref).to eq('o.yaml#/X')
      expect(props['n'].multiple_of).to eq(0.01)
      expect(props['l'].items.type).to eq('integer')
      expect(props['v'].any_of.size).to eq(2)
    end

    it 'handles missing body, single example and no media' do
      spec = build_spec(paths: { '/a' => { 'get' => { 'responses' => { '204' => { 'description' => 'none' } } } } })
      ep = ir_for(spec).endpoints.first
      expect(ep.request_body).to be_nil
      expect(ep.responses.first.media_type).to be_nil
      expect(ep.responses.first.examples).to eq({})
      expect(ep.security).to be_nil
    end
  end
end
