# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Errors do
  let(:rules) { Forge::Rules.load }

  def errors_for(spec)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    described_class.new(spec, rules, roles: roles.value).call
  end

  def for_file(file) = errors_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  def row(finding, status, role) = finding.value[:rows].find { |r| r[:status] == status && r[:role] == role }

  context 'with novapay' do
    subject(:finding) { for_file('examples/specs/novapay.yaml') }

    it 'has 9 rows across roles' do
      expect(finding.value[:rows].map { |r| [r[:status], r[:role]] }.sort).to eq(
        [[400, :create], [401, :create], [402, :create], [409, :create], [422, :create], [429, :create], [500, :create],
         [401, :status], [404, :status], [409, :cancel]].sort
      )
    end

    it 'takes provider codes from examples or first enum' do
      expect(row(finding, 400,
                 :create)).to include(provider_code: 'validation_error', internal_code: 'validation_error',
                                      action: 'reject')
      expect(row(finding, 402, :create)).to include(provider_code: 'insufficient_balance', action: 'retry')
      expect(row(finding, 409, :cancel)).to include(provider_code: 'invalid_status', action: 'reject')
      expect(row(finding, 429, :create)).to include(internal_code: 'rate_limit', action: 'retry_backoff')
      expect(row(finding, 500,
                 :create)).to include(provider_code: nil, internal_code: 'internal_error', action: 'retry')
    end

    it 'treats 409 with the success schema as success' do
      expect(row(finding, 409, :create)).to include(internal_code: 'duplicate', action: 'treat_as_success')
      expect(finding).to have_warning(:duplicate_as_success, level: :info)
      expect(finding.value[:http].keys).to eq([400, 401, 402, 404, 422, 429, 500])
      expect(finding.value[:http][401]).to eq('invalid_credentials')
    end

    it 'finds Retry-After and the code enum' do
      expect(finding.value[:retry_after_header]).to eq('Retry-After')
      expect(finding.value[:codes]).to eq(%w[validation_error insufficient_balance recipient_not_found bank_unavailable
                                             amount_limit_exceeded rate_limit_exceeded internal_error])
    end
  end

  it 'cardpay: code from errors.0.code, 503 retry_backoff' do
    finding = for_file('examples/specs/cardpay.yaml')
    expect(row(finding, 400, :create)).to include(provider_code: 'validation_error', action: 'reject')
    expect(row(finding, 403, :create)).to include(internal_code: 'forbidden', action: 'alert_block')
    expect(row(finding, 503, :create)).to include(action: 'retry_backoff')
    expect(row(finding, 404, :status)).to include(action: 'reject')
    expect(finding.value[:retry_after_header]).to eq('Retry-After')
  end

  it 'swiftpay: problem+json code' do
    finding = for_file('examples/specs/swiftpay.json')
    expect(row(finding, 422, :create)).to include(provider_code: 'validation_error')
    expect(row(finding, 409, :create)).to include(provider_code: 'duplicate_request', action: 'treat_as_success')
  end

  it 'unknown http status without dictionary entry → WARN' do
    op = { 'operationId' => 'createPayout', 'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
           'responses' => { '201' => { 'description' => 'ok' }, '418' => { 'description' => 'teapot' } } }
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => op } }))
    finding = errors_for(spec)
    expect(row(finding, 418, :create)).to include(action: 'reject', internal_code: 'unknown_error')
    expect(finding).to have_warning(:unknown_http_status, hint: /errors\.418/)
  end
end
