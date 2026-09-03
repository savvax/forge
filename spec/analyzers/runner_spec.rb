# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Runner do
  let(:rules) { Forge::Rules.load }

  def run(file) = described_class.run(Forge::IR::Builder.build(Forge::Loader.load(file)), rules: rules)

  def counts(findings) = findings.values.flat_map(&:warnings).group_by(&:level).transform_values(&:size)

  it 'returns 7 findings in a fixed order' do
    expect(run('examples/specs/novapay.yaml').keys).to eq(%i[endpoint_roles auth statuses errors webhooks amount
                                                             fields])
  end

  it 'novapay: exactly 3 WARN + 3 INFO' do
    findings = run('examples/specs/novapay.yaml')
    expect(counts(findings)).to eq(warn: 3, info: 3)
    expect(findings.values.flat_map(&:warnings).map(&:code)).to contain_exactly(
      :conditional_required, :conditional_required, :signature_encoding_assumed,
      :outside_contract, :outside_contract, :duplicate_as_success
    )
  end

  it 'cardpay: 5 WARN + 4 INFO' do
    findings = run('examples/specs/cardpay.yaml')
    expect(counts(findings)).to eq(warn: 5, info: 4)
    expect(findings.values.flat_map(&:warnings).map(&:code)).to include(:production_default, :no_cancel_endpoint)
  end

  it 'swiftpay: 4 WARN + 3 UNSUPPORTED' do
    findings = run('examples/specs/swiftpay.json')
    expect(counts(findings)).to include(warn: 4, unsupported: 3)
  end

  it 'passes include_paths through' do
    spec = Forge::IR::Builder.build(Forge::Loader.load('examples/specs/novapay.yaml'))
    findings = described_class.run(spec, rules: rules, include_paths: ['/balance'])
    expect(findings[:endpoint_roles].value[:create]).to be_nil
  end
end
