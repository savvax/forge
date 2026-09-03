# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Amount do
  let(:rules) { Forge::Rules.load }

  def amount_for(spec)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    described_class.new(spec, rules, roles: roles.value).call
  end

  def for_file(file) = amount_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  def spec_with(properties, required: properties.keys)
    ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                        'operationId' => 'createPayout', 'requestBody' => body_json(properties, required: required),
                        'responses' => { '201' => { 'description' => 'ok' } }
                      } } }))
  end

  it 'novapay: minor units from description, ×100, minimum 1000' do
    finding = for_file('examples/specs/novapay.yaml')
    expect(finding.value).to include(field: 'amount', path: ['amount'], unit: :minor, multiplier: 100,
                                     minimum_major: 1000, currency_field: 'currency', currencies: ['RUB'],
                                     type: 'integer', expr: 'to_minor_units(operation.amount)')
    expect(finding.confidence).to eq(1.0)
    expect(finding.warnings).to eq([])
  end

  it 'cardpay: decimal string → major with format' do
    finding = for_file('examples/specs/cardpay.yaml')
    expect(finding.value).to include(unit: :major, type: 'string', expr: "format('%.2f', operation.amount)",
                                     multiplier: 100)
    expect(finding.confidence).to be >= 0.8
    expect(finding.warnings).to eq([])
  end

  it 'swiftpay: number with multipleOf 0.01 → major' do
    finding = for_file('examples/specs/swiftpay.json')
    expect(finding.value).to include(unit: :major, type: 'number', minimum_major: 1, currencies: %w[EUR USD GBP])
    expect(finding.warnings).to eq([])
  end

  it 'integer without markers → major 0.4 + WARN amount_unit_assumed' do
    finding = amount_for(spec_with({ 'amount' => { 'type' => 'integer' }, 'currency' => { 'type' => 'string' } }))
    expect(finding.value).to include(unit: :major, multiplier: 100)
    expect(finding.confidence).to eq(0.4)
    expect(finding).to have_warning(:amount_unit_assumed, hint: /amount\.unit: minor\|major/)
  end

  it 'JPY → multiplier 1' do
    finding = amount_for(spec_with({ 'amount' => { 'type' => 'integer', 'description' => 'in minor units' },
                                     'currency' => { 'type' => 'string', 'enum' => ['JPY'] } }))
    expect(finding.value).to include(unit: :minor, multiplier: 1)
  end

  it 'finds a nested amount.value' do
    finding = amount_for(spec_with({ 'amount' => { 'type' => 'object', 'properties' => {
                                     'value' => { 'type' => 'integer', 'description' => 'cents' },
                                     'currency' => { 'type' => 'string' }
                                   } } }))
    expect(finding.value).to include(path: %w[amount value], unit: :minor, currency_field: 'amount.currency')
  end

  it 'warns when no amount field exists' do
    finding = amount_for(spec_with({ 'id' => { 'type' => 'string' } }))
    expect(finding.value[:field]).to be_nil
    expect(finding).to have_warning(:amount_field_not_found)
  end
end
