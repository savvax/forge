# frozen_string_literal: true

require 'fileutils'
require 'rack/mock'
require 'base64'

RSpec.describe Forge::Renderers::MockServer do
  def mock_app(name, file)
    dir = "tmp/mock_spec/#{name}"
    FileUtils.rm_rf(dir)
    Forge::Renderers::Runner.render(plan_for(file), out_dir: dir)
    load File.expand_path("#{dir}/mock_server.rb")
    Object.const_get("#{name.capitalize}Mock")
  end

  def post_json(app, path, body, headers = {})
    Rack::MockRequest.new(app).post(path, input: JSON.generate(body), 'CONTENT_TYPE' => 'application/json', **headers)
  end

  # Мок шлёт webhook через Net::HTTP — перехватываем WebMock'ом; возвращаем контейнер с запросом.
  def capture_webhook(url)
    ENV['WEBHOOK_URL'] = url
    received = {}
    stub_request(:post, url).to_return do |req|
      received[:req] = req
      { status: 200, body: '' }
    end
    received
  end

  after { ENV.delete('WEBHOOK_URL') }

  context 'with novapay (api key, minor units, idempotency, callbacks)' do
    let(:app) { mock_app('novapay', 'examples/specs/novapay.yaml') }
    let(:request) do
      app
      JSON.parse(File.read('tmp/mock_spec/novapay/fixtures.json'))['create_request']['request']
    end
    let(:auth) { { 'HTTP_X_API_KEY' => 'test-key' } }

    it 'answers 4xx, never 500, to non-object bodies and non-numeric amounts' do
      client = Rack::MockRequest.new(app)
      ['[]', '"str"', 'not json', '5'].each do |raw|
        expect(client.post('/payouts', auth.merge(input: raw)).status).to eq(400), raw
      end
      [{}, [], 'abc', true].each do |amount|
        expect(post_json(app, '/payouts', request.merge('amount' => amount), auth).status).to eq(201), amount.inspect
      end
    end

    it 'rejects missing api key, small amounts and missing fields' do
      expect(post_json(app, '/payouts', request).status).to eq(401)
      expect(post_json(app, '/payouts', request.merge('amount' => 10), auth).status).to eq(422)
      expect(post_json(app, '/payouts', request.except('recipient'), auth).status).to eq(400)
    end

    it 'creates a payout and repeats it by idempotency key' do
      first = post_json(app, '/payouts', request, auth.merge('HTTP_IDEMPOTENCY_KEY' => 'k1'))
      expect(first.status).to eq(201)
      body = JSON.parse(first.body)
      expect(body).to include('status' => 'pending')
      again = post_json(app, '/payouts', request, auth.merge('HTTP_IDEMPOTENCY_KEY' => 'k1'))
      expect(again.status).to eq(409)
      expect(JSON.parse(again.body)['id']).to eq(body['id'])
    end

    it 'reports status, cancels once and shows balance' do
      id = JSON.parse(post_json(app, '/payouts', request, auth).body)['id']
      expect(JSON.parse(Rack::MockRequest.new(app).get("/payouts/#{id}", auth).body)).to include('id' => id)
      expect(post_json(app, "/payouts/#{id}/cancel", {}, auth).status).to eq(200)
      expect(post_json(app, "/payouts/#{id}/cancel", {}, auth).status).to eq(409)
      expect(JSON.parse(Rack::MockRequest.new(app).get('/balance', auth).body)).to include('balance')
      expect(Rack::MockRequest.new(app).get('/payouts/nope', auth).status).to eq(404)
    end

    it 'simulates an event and sends a signed webhook' do
      received = capture_webhook('http://webhook.test/hook')
      id = JSON.parse(post_json(app, '/payouts', request, auth).body)['id']
      res = post_json(app, "/_simulate/#{id}/payout.completed", {})
      expect(JSON.parse(res.body)).to include('delivered' => true, 'status' => 200)
      expect(JSON.parse(received[:req].body)).to include('event' => 'payout.completed', 'payout_id' => id,
                                                         'status' => 'completed')
      expect(received[:req].headers['X-Novapay-Signature']).to eq(OpenSSL::HMAC.hexdigest('SHA256', 'secret',
                                                                                          received[:req].body))
      expect(JSON.parse(Rack::MockRequest.new(app).get('/_state').body).first).to include('status' => 'completed')
    end
  end

  context 'with cardpay (bearer, base64 sha512, data wrapper)' do
    let(:app) { mock_app('cardpay', 'examples/specs/cardpay.yaml') }

    it 'requires a bearer token and signs with sha512/base64' do
      app
      request = JSON.parse(File.read('tmp/mock_spec/cardpay/fixtures.json'))['create_request']['request']
      expect(post_json(app, '/transfers', request).status).to eq(401)
      created = post_json(app, '/transfers', request, 'HTTP_AUTHORIZATION' => 'Bearer test-key')
      expect(created.status).to eq(201)
      id = JSON.parse(created.body).dig('data', 'transfer_id')
      received = capture_webhook('http://webhook.test/cb')
      post_json(app, "/_simulate/#{id}/transfer.settled", {})
      digest = OpenSSL::HMAC.digest('SHA512', 'secret', received[:req].body)
      expect(received[:req].headers['X-Signature']).to eq(Base64.strict_encode64(digest))
      expect(JSON.parse(received[:req].body)).to include('type' => 'transfer.settled')
    end
  end
end
