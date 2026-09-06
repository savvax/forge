# frozen_string_literal: true

RSpec.describe Forge::Report do
  let(:rules) { Forge::Rules.load }

  def analyze(file)
    spec = Forge::IR::Builder.build(Forge::Loader.load(file), source_path: file)
    [spec, Forge::Analyzers::Runner.run(spec, rules: rules)]
  end

  it 'starts with the lines from the task statement (novapay)' do
    text = described_class.text(*analyze('examples/specs/novapay.yaml'))
    expect(text).to start_with("Parsing spec... ok (openapi 3.0.3, NovaPay Payout API 1.0.0)\n" \
                               'Found 5 endpoints: POST /payouts')
    expect(text).to include(
      'Auth: ApiKeyAuth (api_key, header: X-API-Key) → credentials.api_key',
      'Webhook signature: X-NovaPay-Signature (HMAC-SHA256, raw body, hex) → credentials.callback_secret',
      'Statuses (status): pending, processing → in_progress; completed → approved; failed, cancelled → rejected',
      '409 (create) duplicate → treat_as_success', '409 (cancel) invalid_status → reject',
      'Warnings (3):', 'Info (3):', 'Done: 3 warnings, 0 unsupported. Exit 0.'
    )
  end

  it 'produces json with the agreed keys' do
    spec, findings = analyze('examples/specs/cardpay.yaml')
    json = JSON.parse(described_class.json(spec, findings))
    expect(json.keys).to eq(%w[spec endpoints auth statuses errors webhook amount fields warnings exit_code])
    expect(json['endpoints'].first).to include('role' => 'create', 'operation_id' => 'createTransfer',
                                               'outside_contract' => false)
    expect(json['warnings'].map { |w| w['level'] }.tally).to eq('warn' => 5, 'info' => 4)
  end

  it 'explains exit 3 by the failed generated spec, not by --strict' do
    spec, findings = analyze('examples/specs/novapay.yaml')
    generation = { steps: [], verify: 'FAILED (see error below)', outputs: [], exit_code: 3 }
    expect(described_class.text(spec, findings, generation: generation)).to include('Exit 3. (generated spec failed')
  end

  it 'folds long warning lists' do
    spec, findings = analyze('examples/specs/novapay.yaml')
    extra = Array.new(15) { |i| Forge::Warning.new(level: :warn, code: :x, message: "m#{i}", pointer: nil, hint: nil) }
    findings[:fields] = findings[:fields].with(warnings: findings[:fields].warnings + extra)
    expect(described_class.text(spec, findings)).to include('… and 8 more (see --format json)')
  end

  it 'describes missing auth, webhook and amount gracefully' do
    spec, findings = analyze('spec/fixtures/broken/no_create.yaml')
    text = described_class.text(spec, findings)
    expect(text).to include('Auth: not found', 'Webhook signature: no webhook found', 'Amount: field not found')
  end
end
