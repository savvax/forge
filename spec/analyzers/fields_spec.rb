# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Fields do
  let(:rules) { Forge::Rules.load }

  def fields_for(spec)
    findings = { endpoint_roles: Forge::Analyzers::EndpointRoles.new(spec, rules).call }
    findings[:amount] = Forge::Analyzers::Amount.new(spec, rules, findings: findings).call
    described_class.new(spec, rules, findings: findings).call
  end

  def for_file(file) = fields_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  def mapping(finding, path) = finding.value[:request].find { |m| m.path == path.split('.') }

  context 'with novapay' do
    subject(:finding) { for_file('examples/specs/novapay.yaml') }

    it 'maps root fields' do
      expect(mapping(finding,
                     'amount')).to have_attributes(source_expr: 'to_minor_units(operation.amount)', required: true,
                                                   transform: 'amount', confidence: 0.95)
      expect(mapping(finding, 'currency')).to have_attributes(source_expr: 'operation.currency', required: true)
      expect(mapping(finding, 'external_id')).to have_attributes(source_expr: 'operation.id.to_s', transform: 'to_s')
    end

    it 'maps requisites with conditional requirements' do
      expect(mapping(finding, 'recipient.type')).to have_attributes(source_expr: 'requisite_type', required: true)
      expect(mapping(finding, 'recipient.phone')).to have_attributes(
        source_expr: "operation.payout_requisite.dig(requisite_type, 'phone')", required: true, requisite_type: nil
      )
      expect(mapping(finding, 'recipient.bank_code')).to have_attributes(
        source_expr: "operation.payout_requisite.dig('sbp', 'bank_code')", required: false,
        required_if: { field: 'type', equals: 'sbp' }, requisite_type: 'sbp', confidence: 0.6
      )
      expect(mapping(finding, 'recipient.card_number')).to have_attributes(
        source_expr: "operation.payout_requisite.dig('card', 'number')", required_if: { field: 'type', equals: 'card' }
      )
      expect(mapping(finding, 'recipient.bank_name')).to have_attributes(required: false, requisite_type: 'sbp')
    end

    it 'reports requisite types, headers and exactly two WARN conditional_required' do
      expect(finding.value[:requisite_types]).to eq(%w[sbp card])
      expect(finding.value[:requisite_container]).to eq('recipient')
      expect(finding.value[:headers].map { |h| [h.provider_field, h.source_expr] })
        .to eq([['Idempotency-Key', 'operation.idempotency_key']])
      expect(finding.warnings.map(&:code)).to eq(%i[conditional_required conditional_required])
    end
  end

  def exprs(finding, *paths) = paths.map { |p| mapping(finding, p).source_expr }

  context 'with cardpay' do
    subject(:finding) { for_file('examples/specs/cardpay.yaml') }

    it 'maps credential, reference, callback_url and the nested card container' do
      expect(exprs(finding, 'merchant_id', 'reference', 'callback_url')).to eq(
        ["credentials.fetch('merchant_id')", 'operation.id.to_s', 'callback_url']
      )
      expect(exprs(finding, 'destination.card.pan', 'destination.card.holder', 'destination.card.expiry')).to eq(
        ["operation.payout_requisite.dig('card', 'number')", "operation.payout_requisite.dig('card', 'holder')", nil]
      )
      expect(finding.value[:requisite_types]).to eq(['card'])
    end

    it 'warns about expiry and reports the credential field' do
      expect(finding).to have_warning(:unmapped_field, hint: /fields\.destination\.card\.expiry\.source/)
      expect(finding).to have_warning(:credential_field, level: :info)
    end
  end

  context 'with swiftpay' do
    subject(:finding) { for_file('examples/specs/swiftpay.json') }

    it 'uses the first oneOf variant as bank_account' do
      expect(exprs(finding, 'beneficiary.iban', 'beneficiary.name')).to eq(
        ["operation.payout_requisite.dig('bank_account', 'iban')",
         "operation.payout_requisite.dig('bank_account', 'holder')"]
      )
      expect(mapping(finding, 'purpose').source_expr).to include('operation.description')
      expect(finding.value[:requisite_types]).to eq(['bank_account'])
    end

    it 'warns about the variant and address, external ref is unsupported' do
      expect(finding.warnings.select do |w|
        w.level == :warn
      end.map(&:code)).to eq(%i[one_of_first_variant unmapped_field])
      expect(finding).to have_warning(:external_ref, level: :unsupported)
    end
  end

  it 'raises UnsupportedError for an external ref inside the create request' do
    spec = Forge::IR::Builder.build(Forge::Loader.load('spec/fixtures/broken/external_ref_in_create.yaml'))
    expect { fields_for(spec) }.to raise_error(Forge::UnsupportedError, /external \$ref/)
  end

  it 'arrays → WARN array_field_unsupported' do
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                               'operationId' => 'createPayout',
                               'requestBody' => body_json({ 'amount' => { 'type' => 'integer' },
                                                            'tags' => { 'type' => 'array',
                                                                        'items' => { 'type' => 'string' } } }),
                               'responses' => { '201' => { 'description' => 'ok' } }
                             } } }))
    finding = fields_for(spec)
    expect(mapping(finding, 'tags').source_expr).to eq('[]')
    expect(finding).to have_warning(:array_field_unsupported)
  end
end
