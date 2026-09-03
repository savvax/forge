# frozen_string_literal: true

RSpec.describe Forge::Analyzers::EndpointRoles do
  let(:rules) { Forge::Rules.load }

  def roles_for(file) = described_class.new(Forge::IR::Builder.build(Forge::Loader.load(file)), rules).call

  def ids(value) = value.slice(:create, :status, :cancel, :balance, :webhook).transform_values { |e| e&.operation_id }

  def post_op(path, id, body: true, params: [])
    op = { 'operationId' => id, 'responses' => { '201' => { 'description' => 'ok' } }, 'parameters' => params }
    op['requestBody'] = body_json({ 'amount' => { 'type' => 'integer' } }, required: ['amount']) if body
    { path => { 'post' => op } }
  end

  context 'with novapay' do
    subject(:finding) { roles_for('examples/specs/novapay.yaml') }

    it 'assigns all five roles' do
      expect(ids(finding.value)).to eq(create: 'createPayout', status: 'getPayoutStatus', cancel: 'cancelPayout',
                                       balance: 'getBalance', webhook: 'payoutWebhook')
      expect(finding.value[:other]).to eq([])
    end

    it 'scores 0.95/0.90/0.95/0.90/0.85 and emits no warnings' do
      expect(finding.value[:confidences]).to eq(create: 0.95, status: 0.9, cancel: 0.95, webhook: 0.9, balance: 0.85)
      expect(finding.confidence).to eq(0.95)
      expect(finding.warnings).to eq([])
      expect(finding.source).to include('createPayout')
    end
  end

  context 'with cardpay' do
    subject(:finding) { roles_for('examples/specs/cardpay.yaml') }

    it 'finds create and status, list is other, webhook from callbacks' do
      expect(ids(finding.value)).to include(create: 'createTransfer', status: 'getTransfer', cancel: nil, balance: nil)
      expect(finding.value[:confidences]).to include(create: 0.95, status: 0.9, webhook: 0.95)
      expect(finding.value[:other].map(&:operation_id)).to eq(['listTransfers'])
      expect(finding.value[:webhook].source).to eq(:callbacks)
      expect(finding).to have_warning(:webhook_source_callbacks, level: :info)
    end
  end

  context 'with swiftpay' do
    subject(:finding) { roles_for('examples/specs/swiftpay.json') }

    it 'finds cancel via DELETE and balance' do
      expect(ids(finding.value)).to eq(create: 'initiateOutboundPayment', status: 'getOutboundPayment',
                                       cancel: 'cancelOutboundPayment', balance: 'getAccountBalance',
                                       webhook: 'paymentStatusChanged')
      expect(finding).to have_warning(:webhook_source_webhooks, level: :info)
    end

    it 'accepts DELETE as cancel with 0.85 (method_delete signal)' do
      expect(finding.value[:confidences][:cancel]).to eq(0.85)
      expect(finding.warnings.map(&:level)).to eq([:info])
    end
  end

  context 'with literal specs' do
    it 'treats GET /payouts (list) as other' do
      spec = build_spec(paths: { '/payouts' => { 'get' => { 'operationId' => 'listPayouts',
                                                            'responses' => { '200' => { 'description' => 'ok' } } } } })
      value = described_class.new(ir_for(spec), rules).call.value
      expect(value[:status]).to be_nil
      expect(value[:other].map(&:operation_id)).to eq(['listPayouts'])
    end

    it 'resolves two create candidates: higher score wins, loser is other + WARN role_conflict' do
      spec = build_spec(paths: post_op('/payouts', 'createPayout').merge(post_op('/payouts/batch', 'submitPayouts')))
      finding = described_class.new(ir_for(spec), rules).call
      expect(finding.value[:create].operation_id).to eq('createPayout')
      expect(finding.value[:other].map(&:operation_id)).to eq(['submitPayouts'])
      expect(finding).to have_warning(:role_conflict, hint: /endpoints\.submitPayouts: create/)
    end

    it 'penalises negative words' do
      finding = described_class.new(ir_for(build_spec(paths: post_op('/v2/transfer-orders', 'createTransferOrder'))),
                                    rules).call
      expect(finding.value[:confidences][:create]).to be < 0.8
      expect(finding).to have_warning(:low_confidence)
    end

    it 'filters by include_paths' do
      spec = build_spec(paths: post_op('/v1/payouts', 'createPayout').merge(post_op('/v1/orders', 'createOrder')))
      value = described_class.new(ir_for(spec), rules, include_paths: ['/v1/payouts*']).call.value
      expect(value[:create].operation_id).to eq('createPayout')
      expect(value[:other]).to eq([])
    end

    it 'warns when include_paths matches nothing' do
      finding = described_class.new(ir_for(build_spec(paths: post_op('/payouts', 'createPayout'))), rules,
                                    include_paths: ['/nope*']).call
      expect(finding.value[:create]).to be_nil
      expect(finding).to have_warning(:include_paths_empty)
    end

    it 'warns needs_override when no create endpoint is found' do
      spec = build_spec(paths: { '/balance' => { 'get' => { 'operationId' => 'getBalance',
                                                            'responses' => { '200' => { 'description' => 'ok' } } } } })
      finding = described_class.new(ir_for(spec), rules).call
      expect(finding.value[:create]).to be_nil
      expect(finding).to have_warning(:no_create_endpoint, hint: /endpoints\.<operationId>: create/)
    end

    it 'accepts a status endpoint identified by an id query param' do
      param = { 'name' => 'reference', 'in' => 'query', 'schema' => { 'type' => 'string' } }
      paths = { '/payout' => { 'get' => { 'operationId' => 'getPayout', 'parameters' => [param],
                                          'responses' => { '200' => { 'description' => 'ok' } } } } }
      value = described_class.new(ir_for(build_spec(paths: paths)), rules).call.value
      expect(value[:status]&.operation_id).to eq('getPayout')
    end
  end
end
