# frozen_string_literal: true

require 'provider'

RSpec.describe Forge::Renderers::Service do
  def render(plan, templates_dir: nil) = described_class.new(plan, templates_dir: templates_dir).render

  def write(plan, name)
    path = "tmp/#{name}"
    File.write(path, render(plan))
    path
  end

  def minimal_spec(auth: 'bearer', schemes: nil, security: nil)
    schemes ||= { 'b' => { 'type' => 'http', 'scheme' => auth } }
    build_spec(security_schemes: schemes, security: security || [{ schemes.keys.first => [] }], paths: {
                 '/payouts' => { 'post' => {
                   'operationId' => 'createPayout',
                   'requestBody' => body_json({ 'amount' => { 'type' => 'string', 'pattern' => '^\d+\.\d{2}$' },
                                                'currency' => { 'type' => 'string' },
                                                'reference' => { 'type' => 'string' } }),
                   'responses' => response_json(201, { 'id' => { 'type' => 'string' },
                                                       'status' => { 'type' => 'string', 'enum' => %w[pending paid] } })
                 } }
               })
  end

  it 'renders novapay byte-for-byte equal to the golden file' do
    expect(render(plan_for('examples/specs/novapay.yaml'))).to eq(File.read('spec/golden/novapay/novapay_service.rb'))
  end

  it 'renders a loadable service for all three specs' do
    %w[novapay.yaml cardpay.yaml swiftpay.json].each do |file|
      path = write(plan_for("examples/specs/#{file}"), "#{file}_service.rb")
      expect(Forge::Verifier.syntax!([path])).to eq([path])
    end
  end

  it 'loads the novapay service and instantiates it' do
    path = write(plan_for('examples/specs/novapay.yaml'), 'load_novapay_service.rb')
    load File.expand_path(path)
    record = Provider::Record.new(name: 'novapay', credentials: { 'api_key' => 'k' })
    expect(Provider::NovapayService.new(provider: record)).to be_a(Provider::BaseService)
  end

  context 'with a minimal plan (bearer, major string, no webhook/status/cancel)' do
    subject(:code) { render(plan_for_hash(minimal_spec)) }

    it 'is valid ruby with stubs and no helpers' do
      expect(Forge::Verifier.syntax!([write(plan_for_hash(minimal_spec), 'minimal_service.rb')])).to be_truthy
      expect(code).to include("failure(:not_implemented, 'callbacks_not_supported')",
                              "failure(:not_implemented, 'status_endpoint_missing')",
                              %q('Authorization' => "Bearer #{credentials.fetch('token')}"),
                              "format('%.2f', operation.amount)")
      expect(code).not_to include('cancel_request', 'fetch_balance', 'EVENT_MAP', 'to_minor_units', 'build_recipient')
    end
  end

  it 'reads nil instead of a status when the status endpoint returns a list' do
    hash = minimal_spec
    list = { 'type' => 'array', 'items' => { 'type' => 'object' } }
    hash['paths']['/payouts/{id}/status'] = { 'get' => {
      'operationId' => 'getPayoutStatus',
      'parameters' => [{ 'name' => 'id', 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }],
      'responses' => { '200' => { 'description' => 'ok', 'content' => { 'application/json' => { 'schema' => list } } } }
    } }
    code = render(plan_for_hash(hash))
    expect(code).to include('apply_status(operation, nil, strict: true)')
    expect(code).not_to include("response.body['status'], strict: true")
  end

  it 'renders basic auth with Base64' do
    code = render(plan_for_hash(minimal_spec(auth: 'basic')))
    expect(code).to include("require 'base64'", 'Base64.strict_encode64("#{credentials.fetch(\'login\')}:' \
                                                '#{credentials.fetch(\'password\')}")')
  end

  it 'renders base64 signatures, TODOs and a delete cancel (cardpay, swiftpay)' do
    cardpay = render(plan_for('examples/specs/cardpay.yaml'))
    expect(cardpay).to include("Base64.strict_encode64(OpenSSL::HMAC.digest('SHA512'",
                               "expiry: nil, # TODO(forge): map 'destination.card.expiry'")
    swiftpay_plan = plan_for('examples/specs/swiftpay.json')
    expect(render(swiftpay_plan)).to include('raise NotImplementedError', 'operation.amount.to_f.round(2)')
    expect(render(swiftpay_plan)).not_to include('def cancel_request')
    expect(Forge::Renderers::Extras.new(swiftpay_plan).render).to include('class SwiftpayExtras < SwiftpayService',
                                                                          'client.delete(')
  end

  def form_status_spec
    body = { 'required' => true, 'content' => { 'application/x-www-form-urlencoded' => { 'schema' => {
      'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer', 'description' => 'in cents' },
                                            'currency' => { 'type' => 'string' } }
    } } } }
    ok = response_json(200, { 'id' => { 'type' => 'string' }, 'status' => { 'type' => 'string', 'enum' => %w[paid] } })
    create = { 'operationId' => 'transferCreate', 'requestBody' => body, 'responses' => ok }
    status = { 'operationId' => 'transferGet', 'requestBody' => body_json({ 'transfer_id' => { 'type' => 'string' } }),
               'responses' => ok }
    build_spec(security_schemes: { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } }, security: [{ 'b' => [] }],
               paths: { '/transfer/create' => { 'post' => create }, '/transfer/get' => { 'post' => status } })
  end

  context 'with a form-urlencoded create and a POST status (id in the body)' do
    let(:plan) { plan_for_hash(form_status_spec) }

    it 'plans form encoding and the status request field' do
      expect(plan.operations[:create].body_encoding).to eq('form')
      expect(plan.operations[:status].status_request_field).to eq('transfer_id')
      expect(plan.warnings.map(&:code)).to include(:media_type_form)
    end

    it 'renders form: payload and a POST fetch_status, and the generated spec is green' do
      expect(render(plan)).to include('form: payload', "body = { 'transfer_id' => operation.provider_operation_key }",
                                      '/transfer/get", json: body, headers: auth_headers)')
      dir = 'tmp/form_status'
      Forge::Renderers::Runner.render(plan, out_dir: dir, force: true)
      expect(Forge::Verifier.spec!("#{dir}/test_service_spec.rb", load_paths: ['lib', dir])).to include('0 failures')
    end
  end

  it 'renders an empty STATUS_MAP with a TODO when the spec has no status enum' do
    ok = response_json(200, { 'id' => { 'type' => 'string' }, 'note' => { 'type' => 'string' } })
    body = body_json({ 'amount' => { 'type' => 'integer' } })
    op = { 'operationId' => 'createPayout', 'responses' => ok, 'requestBody' => body }
    schemes = { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } }
    spec = build_spec(security_schemes: schemes, security: [{ 'b' => [] }], paths: { '/payouts' => { 'post' => op } })
    plan = plan_for_hash(spec)
    expect(plan.status_map).to eq({})
    dir = 'tmp/no_statuses'
    files = Forge::Renderers::Runner.render(plan, out_dir: dir, force: true).map { |f| f[:path] }
    expect(File.read("#{dir}/test_service.rb")).to include('STATUS_MAP = {}.freeze # TODO(forge)')
    expect(Forge::Verifier.syntax!(files.grep(/\.rb\z/))).to be_truthy
  end

  it 'raises VerificationError with compiler output for a broken template' do
    FileUtils.mkdir_p('tmp/templates')
    File.write('tmp/templates/service.rb.erb', "class Broken\n  def x(\nend\n")
    path = write(plan_for('examples/specs/novapay.yaml'), 'broken_service.rb') # default templates
    File.write(path,
               described_class.new(plan_for('examples/specs/novapay.yaml'), templates_dir: 'tmp/templates').render)
    expect { Forge::Verifier.syntax!([path]) }.to raise_error(Forge::VerificationError, /syntax error/)
  end

  it 'raises GenerationError when the template is missing' do
    renderer = Class.new(Forge::Renderers::Base) do
      def template_name
        'nope.erb'
      end
    end.new(plan_for('examples/specs/novapay.yaml'))
    expect { renderer.render }.to raise_error(Forge::GenerationError, /template not found/)
  end
end
