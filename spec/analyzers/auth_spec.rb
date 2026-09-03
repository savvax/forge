# frozen_string_literal: true

RSpec.describe Forge::Analyzers::Auth do
  let(:rules) { Forge::Rules.load }

  def auth_for(spec)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    described_class.new(spec, rules, roles: roles.value).call
  end

  def auth_for_file(file) = auth_for(Forge::IR::Builder.build(Forge::Loader.load(file)))

  def spec_with(schemes, security)
    ir_for(build_spec(security_schemes: schemes, security: security, paths: {
                        '/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                    'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
                                                    'responses' => { '201' => { 'description' => 'ok' } } } }
                      }))
  end

  it 'novapay: apiKey header X-API-Key → api_key 0.95' do
    finding = auth_for_file('examples/specs/novapay.yaml')
    expect(finding.value).to include(type: 'api_key', scheme_name: 'ApiKeyAuth', header: 'X-API-Key', prefix: nil,
                                     credential_key: 'api_key', credential_keys: ['api_key'], location: 'header')
    expect(finding.confidence).to eq(0.95)
    expect(finding.warnings).to eq([])
  end

  it 'cardpay: bearer from root security → token' do
    finding = auth_for_file('examples/specs/cardpay.yaml')
    expect(finding.value).to include(type: 'bearer', header: 'Authorization', prefix: 'Bearer', credential_key: 'token')
  end

  it 'swiftpay: basic wins, oauth2 alternative is UNSUPPORTED' do
    finding = auth_for_file('examples/specs/swiftpay.json')
    expect(finding.value).to include(type: 'basic', credential_keys: %w[login password], header: 'Authorization')
    expect(finding).to have_warning(:oauth2_alternative, level: :unsupported)
  end

  it 'apiKey in query → WARN' do
    finding = auth_for(spec_with({ 'k' => { 'type' => 'apiKey', 'in' => 'query', 'name' => 'key' } }, [{ 'k' => [] }]))
    expect(finding.value).to include(type: 'api_key', location: 'query', header: nil)
    expect(finding).to have_warning(:api_key_in_query, level: :warn)
  end

  it 'oauth2 only → UNSUPPORTED + bearer fallback' do
    finding = auth_for(spec_with({ 'o' => { 'type' => 'oauth2', 'flows' => {} } }, [{ 'o' => [] }]))
    expect(finding.value).to include(type: 'bearer', credential_key: 'token')
    expect(finding).to have_warning(:oauth2, level: :unsupported, hint: /token/)
  end

  it 'no security → WARN auth_not_found' do
    finding = auth_for(spec_with({}, nil))
    expect(finding.value[:type]).to eq('none')
    expect(finding).to have_warning(:auth_not_found, level: :warn)
  end

  it 'unknown scheme reference → WARN' do
    finding = auth_for(spec_with({}, [{ 'ghost' => [] }]))
    expect(finding).to have_warning(:auth_scheme_missing, level: :warn)
  end
end
