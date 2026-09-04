# frozen_string_literal: true

RSpec.describe Forge::Plan::Overrides do
  let(:rules) { Forge::Rules.load }

  def analyze(file, overrides)
    spec = Forge::IR::Builder.build(Forge::Loader.load(file), source_path: file)
    findings = Forge::Analyzers::Runner.run(spec, rules: rules, overrides: overrides)
    [spec, findings, Forge::Plan::Builder.build(spec, findings, overrides: overrides)]
  end

  def warnings(findings) = findings.values.flat_map(&:warnings)
  def applied(findings) = warnings(findings).select { |w| w.code == :override_applied }.map(&:message)

  it 'loads and validates a file, rejecting unknown keys with did-you-mean' do
    File.write('tmp/bad.yml', "statusses:\n  X: approved\n")
    expect { described_class.load('tmp/bad.yml') }
      .to raise_error(Forge::SpecError, /unknown overrides key 'statusses'.*did you mean statuses\?/m)
    File.write('tmp/bad2.yml', "fields:\n  a.b:\n    sourse: x\n")
    expect do
      described_class.load('tmp/bad2.yml')
    end.to raise_error(Forge::SpecError, /did you mean fields\.a\.b\.source/)
    expect { described_class.load('tmp/none.yml') }.to raise_error(Forge::SpecError, /not found/)
  end

  context 'with examples/overrides/cardpay.yml' do
    let(:result) { analyze('examples/specs/cardpay.yaml', described_class.load('examples/overrides/cardpay.yml')) }

    it 'closes all 5 WARN with 4 override_applied' do
      expect(warnings(result[1]).select { |w| w.level == :warn }).to eq([])
      expect(applied(result[1]).size).to eq(4)
    end

    it 'changes the plan accordingly' do
      plan = result[2]
      expect(plan.base_url[:default]).to eq('https://sandbox.cardpay.example/v2')
      expect(plan.status_map['ON_HOLD']).to eq('in_progress')
      expect(plan.event_map['transfer.on_hold']).to eq('in_progress')
      expect(plan.fields[:request].find { |m| m.path == %w[destination card expiry] }.source_expr)
        .to start_with("format('%02d")
    end
  end

  it 'swiftpay.yml closes the closable WARNs' do
    _spec, findings, = analyze('examples/specs/swiftpay.json', described_class.load('examples/overrides/swiftpay.yml'))
    expect(warnings(findings).select { |w| w.level == :warn }.map(&:code)).to eq([:one_of_first_variant])
  end

  it 'novapay.yml confirms conditional requirements and encoding' do
    _spec, findings, = analyze('examples/specs/novapay.yaml', described_class.load('examples/overrides/novapay.yml'))
    expect(warnings(findings).select { |w| w.level == :warn }).to eq([])
  end

  context 'with single keys on novapay' do
    def novapay(overrides) = analyze('examples/specs/novapay.yaml', overrides)

    it 'provider' do
      expect(novapay('provider' => { 'name' => 'nova', 'class_name' => 'NovaSvc' })[2].provider)
        .to include(name: 'nova', class_name: 'NovaSvc', env_prefix: 'NOVA')
    end

    it 'paths.include' do
      _s, findings, = novapay('paths' => { 'include' => ['/balance'] })
      expect(findings[:endpoint_roles].value[:create]).to be_nil
    rescue Forge::GenerationError
      # план без create не строится — ожидаемо
    end

    it 'endpoints reassigns a role and cannot invent one' do
      _s, findings, plan = novapay('endpoints' => { 'cancelPayout' => 'other' })
      expect(findings[:endpoint_roles].value[:cancel]).to be_nil
      expect(plan.operations[:cancel]).to be_nil
      expect(applied(findings)).to include('endpoints.cancelPayout → other')
      expect { novapay('endpoints' => { 'nope' => 'create' }) }.to raise_error(Forge::SpecError, /no such operationId/)
    end

    it 'auth' do
      _s, findings, = novapay('auth' => { 'type' => 'bearer', 'header' => 'Authorization',
                                          'credential_key' => 'token' })
      expect(findings[:auth].value).to include(type: 'bearer', credential_keys: ['token'])
    end

    it 'events' do
      _s, findings, = novapay('events' => { 'payout.completed' => 'rejected' })
      expect(findings[:webhooks].value[:event_map]['payout.completed']).to eq('rejected')
    end

    it 'amount' do
      _s, findings, plan = novapay('amount' => { 'unit' => 'major', 'multiplier' => 1, 'minimum_major' => 5 })
      expect(findings[:amount].value).to include(unit: :major, multiplier: 1, minimum_major: 5,
                                                 expr: 'operation.amount')
      expect(plan.validations.first).to include(rule: :min, value: 5)
    end

    it 'fields source / required / required_if' do
      _s, findings, = novapay('fields' => { 'recipient.bank_name' => { 'source' => "'X'", 'required' => true },
                                            'recipient.bank_code' => { 'required_if' => { 'field' => 'type',
                                                                                          'equals' => 'card' } } })
      by_path = findings[:fields].value[:request].to_h { |m| [m.path.join('.'), m] }
      expect(by_path['recipient.bank_name']).to have_attributes(source_expr: "'X'", required: true)
      expect(by_path['recipient.bank_code'].required_if).to eq(field: 'type', equals: 'card')
      expect(warnings(findings).count { |w| w.code == :conditional_required }).to eq(1)
    end

    it 'webhook keys' do
      _s, findings, = novapay('webhook' => { 'signature_encoding' => 'base64', 'id_field' => 'data.id' })
      expect(findings[:webhooks].value[:signature][:encoding]).to eq('base64')
      expect(findings[:webhooks].value[:id_field]).to eq(%w[data id])
      expect(warnings(findings).map(&:code)).not_to include(:signature_encoding_assumed)
    end

    it 'errors by status and by provider code' do
      _s, findings, plan = novapay('errors' => { 409 => { 'action' => 'reject', 'internal_code' => 'duplicate' },
                                                 'insufficient_balance' => { 'action' => 'alert' } })
      expect(plan.success_statuses).to eq([201])
      expect(plan.error_map[409]).to include(action: 'reject', internal_code: 'duplicate')
      expect(plan.error_map[402][:action]).to eq('alert')
      expect(warnings(findings).map(&:code)).not_to include(:duplicate_as_success)
    end
  end
end
