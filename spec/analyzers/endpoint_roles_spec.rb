# frozen_string_literal: true

RSpec.describe Forge::Analyzers::EndpointRoles do
  let(:rules) { Forge::Rules.load }

  def roles_for(file) = described_class.new(Forge::IR::Builder.build(Forge::Loader.load(file)), rules).call

  def ids(value) = value.slice(:create, :status, :cancel, :balance, :webhook).transform_values { |e| e&.operation_id }

  def path_param(name) = { 'name' => name, 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }

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
      expect(finding.value[:create]).to be_nil # 0.95 − 0.5 < warn threshold
      expect(finding).to have_warning(:no_create_endpoint)
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

    it 'rejects a status candidate whose 2xx body is an array (list, not a status)' do
      list = { 'type' => 'array', 'items' => { 'type' => 'object' } }
      ok = { 'description' => 'ok', 'content' => { 'application/json' => { 'schema' => list } } }
      paths = { '/wallet/{walletId}/paymentIds' => { 'get' => {
        'operationId' => 'paymentIds', 'parameters' => [path_param('walletId')], 'responses' => { '200' => ok }
      } } }
      value = described_class.new(ir_for(build_spec(paths: paths)), rules).call.value
      expect(value[:status]).to be_nil
    end

    it 'penalises a status endpoint with several path params (only one id comes from the operation)' do
      paths = { '/client/{clientId}/payment/{paymentId}' => { 'get' => {
        'operationId' => 'getPayment', 'parameters' => [path_param('clientId'), path_param('paymentId')],
        'responses' => { '200' => { 'description' => 'ok' } }
      } } }
      finding = described_class.new(ir_for(build_spec(paths: paths)), rules).call
      expect(finding.value[:confidences][:status]).to be < 0.8
      expect(finding).to have_warning(:low_confidence, hint: /endpoints\.getPayment: status/)
    end

    it 'counts payment as a payout word when the spec has no stronger one' do
      finding = described_class.new(ir_for(build_spec(paths: post_op('/v1/payments', 'createPayment'))), rules).call
      expect(finding.value[:confidences][:create]).to eq(0.95)
    end

    it 'rejects a create candidate off the payout resource (Square: /v2/payments next to /v2/payouts)' do
      get_payout = { 'operationId' => 'GetPayout', 'parameters' => [path_param('payout_id')],
                     'responses' => { '200' => { 'description' => 'ok' } } }
      paths = post_op('/v2/payments', 'CreatePayment').merge('/v2/payouts/{payout_id}' => { 'get' => get_payout })
      finding = described_class.new(ir_for(build_spec(paths: paths)), rules).call
      expect(finding.value[:create]).to be_nil
      expect(finding.value[:status].operation_id).to eq('GetPayout')
    end

    it 'drops status/cancel candidates off the payout resource when there is no create (pay-in spec)' do
      paths = { '/static-qr/{id}' => { 'get' => { 'operationId' => 'getStaticQr', 'parameters' => [path_param('id')],
                                                  'responses' => { '200' => { 'description' => 'ok' } } } } }
      finding = described_class.new(ir_for(build_spec(paths: paths)), rules).call
      expect(finding.value.values_at(:create, :status, :cancel)).to all(be_nil)
      expect(finding).not_to have_warning(:low_confidence)
    end

    it 'treats sandbox simulation and inward payment endpoints as negative' do
      finding = described_class.new(ir_for(build_spec(paths: post_op('/inward/payment/manual', 'simulatePayment'))),
                                    rules).call
      expect(finding.value[:create]).to be_nil
    end

    it 'reports UNSUPPORTED path params that cannot be filled from the operation' do
      create = post_op('/client/{clientId}/payouts', 'createPayout', params: [path_param('clientId')])
      status = { '/client/{clientId}/payouts/{payoutId}' => { 'get' => {
        'operationId' => 'getPayout', 'parameters' => [path_param('clientId'), path_param('payoutId')],
        'responses' => { '200' => { 'description' => 'ok' } }
      } } }
      finding = described_class.new(ir_for(build_spec(paths: create.merge(status))), rules).call
      expect(finding).to have_warning(:path_params_unresolved, level: :unsupported, message: /createPayout.*clientId/)
      expect(finding).to have_warning(:path_params_unresolved, level: :unsupported, message: /getPayout.*clientId/)
      expect(finding.warnings.count { |w| w.code == :path_params_unresolved }).to eq(2)
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
