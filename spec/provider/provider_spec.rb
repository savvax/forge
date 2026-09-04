# frozen_string_literal: true

require 'provider'

RSpec.describe Provider do
  describe Provider::Result do
    it 'knows success and failure' do
      expect(described_class.new(status: :ok, code: nil, data: {})).to be_success
      expect(described_class.new(status: :not_found, code: 'x', data: {})).to be_failed
    end
  end

  describe Provider::Operation do
    it 'defaults status, requisites and idempotency key' do
      op = described_class.new(id: 'op_1', amount: 10, currency: 'RUB')
      expect(op.status).to eq('new')
      expect(op.payout_requisite).to eq({})
      expect(op.idempotency_key).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    end
  end

  describe Provider::MemoryOperations do
    subject(:store) { described_class.new }

    let(:op) { Provider::Operation.new(id: 'op_1', amount: 10, currency: 'RUB') }

    it 'saves, finds and updates' do
      store.save(op)
      store.update('op_1', provider_operation_id: 'np_1', status: 'in_progress')
      expect(store.find('op_1').provider_operation_id).to eq('np_1')
      expect(store.find_by_provider_id('np_1').status).to eq('in_progress')
      expect(store.find_by_provider_id('nope')).to be_nil
    end
  end

  describe Provider::HttpClient do
    subject(:client) { described_class.new }

    let(:url) { 'https://api.test.example/v1/payouts' }

    it 'parses JSON responses' do
      stub_request(:post, url).with(headers: { 'Content-Type' => 'application/json' }).to_return(status: 200,
                                                                                                 body: '{"id":"x"}')
      expect(client.post(url, json: { a: 1 }).body).to eq('id' => 'x')
    end

    it 'raises typed errors' do
      stub_request(:get, url).to_return(status: 401)
      expect { client.get(url) }.to raise_error(Provider::UnauthorizedError)
      stub_request(:get, "#{url}?a=1").to_return(status: 429, headers: { 'Retry-After' => '60' })
      expect { client.get(url, params: { a: 1 }) }.to raise_error(Provider::RateLimitError) { |e| expect(e.retry_after).to eq(60) }
      stub_request(:delete, url).to_return(status: 503)
      expect { client.delete(url) }.to raise_error(Provider::ServerError) { |e| expect(e.status).to eq(503) }
    end

    it 'wraps timeouts, keeps raw bodies and sends forms' do
      stub_request(:get, url).to_timeout
      expect { client.get(url) }.to raise_error(Provider::ConnectionError)
      stub_request(:post, url).with(headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
                              .to_return(status: 200, body: 'not json')
      expect(client.post(url, form: { a: 1 }).body).to eq('raw' => 'not json')
    end
  end

  describe Provider::BaseService do
    subject(:service) { described_class.new(provider: record) }

    let(:record) { Provider::Record.new(name: 'x', credentials: { 'api_key' => 'k' }, config: { 'callback_url' => 'cb' }) }

    it 'checks amount and requisites' do
      expect(service.check_conditions(Provider::Operation.new(id: '1', amount: 0), 'sbp').code).to eq('amount_invalid')
      expect(service.check_conditions(Provider::Operation.new(id: '1', amount: 5),
                                      'sbp').code).to eq('requisite_missing')
      op = Provider::Operation.new(id: '1', amount: 5, payout_requisite: { 'sbp' => {} })
      expect(service.check_conditions(op, 'sbp')).to be_success
    end

    it 'reports unknown operations and reads config' do
      expect(service.approve_operation('nope').code).to eq('operation_not_found')
      expect(service.callback_url).to eq('cb')
      expect(service.credentials['api_key']).to eq('k')
    end

    it 'finds rack-style headers and compares securely' do
      expect(service.send(:header_value, { 'HTTP_X_SIGNATURE' => 'abc' }, 'X-Signature')).to eq('abc')
      expect(service.send(:secure_compare, nil, 'x')).to be(false)
      expect(service.send(:secure_compare, 'x', 'x')).to be(true)
    end

    it 'raises NotImplementedError for contract methods' do
      expect { service.create_request(nil) }.to raise_error(NotImplementedError)
      expect { service.fetch_status(nil) }.to raise_error(NotImplementedError)
      expect { service.process_callback({}) }.to raise_error(NotImplementedError)
    end
  end
end
