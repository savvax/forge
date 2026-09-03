# frozen_string_literal: true

RSpec.describe Forge::Plan::Builder do
  let(:rules) { Forge::Rules.load }

  def plan_for(file, provider: nil)
    spec = Forge::IR::Builder.build(Forge::Loader.load(file), source_path: file)
    findings = Forge::Analyzers::Runner.run(spec, rules: rules)
    described_class.build(spec, findings, provider_name: provider)
  end

  context 'with novapay' do
    subject(:plan) { plan_for('examples/specs/novapay.yaml') }

    it 'names the provider and base url' do
      expect(plan.provider).to eq(name: 'novapay', class_name: 'NovapayService', env_prefix: 'NOVAPAY',
                                  file_name: 'novapay_service.rb', title: 'NovaPay Payout API')
      expect(plan.base_url).to eq(default: 'https://api.sandbox.novapay.example/v1',
                                  production: 'https://api.novapay.example/v1', env_var: 'NOVAPAY_BASE_URL')
    end

    it 'builds operations and success statuses' do
      expect(plan.operations.keys).to eq(%i[create status cancel balance])
      expect(plan.operations[:create]).to have_attributes(method: 'post', path: '/payouts',
                                                          success_statuses: [201, 409], response_id_path: ['id'],
                                                          response_status_path: ['status'])
      expect(plan.operations[:status].path_params).to eq(['payout_id'])
      expect(plan.success_statuses).to eq([201, 409])
      expect(plan.operations[:cancel]).not_to be_nil
    end

    it 'has 4 validations, status/error maps and amount' do
      expect(plan.validations.map { |v| v[:error_code] }).to eq(%w[amount_too_low external_id_too_long phone_invalid
                                                                   currency_not_supported])
      expect(plan.amount[:minimum_major]).to eq(1000)
      expect(plan.status_map).to include('completed' => 'approved')
      expect(plan.error_map.keys).to eq([400, 401, 402, 404, 422, 429, 500])
      expect(plan.error_map[429]).to include(internal_code: 'rate_limit', action: 'retry_backoff')
    end

    it 'lists outside-contract endpoints, gateway config and 6 warnings' do
      expect(plan.outside_contract.map { |o| o[:helper] }).to eq(%w[cancel_request fetch_balance])
      expect(plan.gateway_config).to eq([{ external_method: 'sbp_payout', gateway: 'RUB_SBP_WITHDRAW' },
                                         { external_method: 'card_payout', gateway: 'RUB_CARD_WITHDRAW' }])
      expect(plan.warnings.size).to eq(6)
      expect(plan.meta).to eq(spec_title: 'NovaPay Payout API', spec_version: '1.0.0',
                              spec_file: 'examples/specs/novapay.yaml', forge_version: '1.0.0')
    end

    it 'builds the create fixture and the operation from the request example' do
      create = plan.fixtures['create_request']
      expect(create['request']['recipient']['phone']).to eq('79001234567')
      expect(create['operation']).to eq('id' => 'op_abc123', 'amount' => '15000.00', 'currency' => 'RUB',
                                        'payout_requisite' => { 'sbp' => { 'phone' => '79001234567',
                                                                           'bank_code' => '044525225',
                                                                           'bank_name' => 'Сбербанк' } })
      expect(create['expected_operation_status']).to eq('in_progress')
    end

    it 'builds callback and auth fixtures' do
      expect(plan.fixtures['callback']['expected_operation_status']).to eq('approved')
      expect(plan.fixtures['callback_failed']['payload']['event']).to eq('payout.failed')
      expect(plan.fixtures['auth']).to eq('headers' => { 'X-API-Key' => '<credentials.api_key>' })
    end

    it 'is deterministic' do
      expect(plan).to eq(plan_for('examples/specs/novapay.yaml'))
    end
  end

  it 'uses --provider for naming' do
    plan = plan_for('examples/specs/novapay.yaml', provider: 'Nova Pay')
    expect(plan.provider).to include(class_name: 'NovaPayService', env_prefix: 'NOVA_PAY',
                                     file_name: 'nova_pay_service.rb')
  end

  it 'cardpay: name from title, production default, no cancel, bearer auth fixture' do
    plan = plan_for('examples/specs/cardpay.yaml')
    expect(plan.provider[:name]).to eq('cardpay')
    expect(plan.base_url).to include(default: 'https://api.cardpay.example/v2',
                                     production: 'https://api.cardpay.example/v2')
    expect(plan.operations[:cancel]).to be_nil
    expect(plan.fixtures['auth']).to eq('headers' => { 'Authorization' => 'Bearer <credentials.token>' })
    expect(plan.gateway_config).to eq([{ external_method: 'card_payout', gateway: 'RUB_CARD_WITHDRAW' }])
  end

  it 'swiftpay: name, basic auth, bank_account gateway, delete cancel' do
    plan = plan_for('examples/specs/swiftpay.json')
    expect(plan.provider[:name]).to eq('swiftpay')
    expect(plan.fixtures['auth']['headers']['Authorization']).to start_with('Basic ')
    expect(plan.gateway_config).to eq([{ external_method: 'bank_account_payout',
                                         gateway: 'EUR_BANK_ACCOUNT_WITHDRAW' }])
    expect(plan.operations[:cancel].method).to eq('delete')
    expect(plan.fixtures['callback']['expected_operation_status']).to eq('approved')
  end

  it 'raises GenerationError without a create endpoint' do
    expect { plan_for('spec/fixtures/broken/no_create.yaml') }
      .to raise_error(Forge::GenerationError, /no create endpoint.*hint: .*endpoints\.<operationId>: create/m)
  end
end
