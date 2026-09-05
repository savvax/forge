# frozen_string_literal: true

RSpec.describe Forge::Loader do
  it 'hints that an overrides file was passed as a spec' do
    expect { described_class.load('examples/overrides/raiffeisen.yml') }
      .to raise_error(Forge::SpecError, /looks like overrides.yml/)
  end

  def broken(name) = "spec/fixtures/broken/#{name}"

  {
    'not_yaml.yaml' => 'cannot parse',
    'empty.yaml' => 'empty document',
    'not_object.yaml' => 'root must be an object',
    'swagger2.yaml' => 'Swagger 2.0 is not supported; convert to OpenAPI 3',
    'no_openapi_key.json' => "missing 'openapi'",
    'no_paths.yaml' => 'no paths'
  }.each do |file, text|
    it "#{file} raises SpecError with '#{text}' and the file name" do
      expect { described_class.load(broken(file)) }
        .to raise_error(Forge::SpecError) { |e| expect(e.message).to include(text, file) }
    end
  end

  it 'marks a missing local $ref target (analyzer decides, D-14)' do
    spec = described_class.load(broken('bad_ref.yaml'))
    schema = spec.dig('paths', '/payouts', 'post', 'requestBody', 'content', 'application/json', 'schema')
    expect(schema).to include('x-forge-unresolved' => '#/components/schemas/Missing')
  end

  it 'marks a circular $ref with the chain instead of raising (D-14)' do
    spec = described_class.load(broken('cyclic_ref.yaml'))
    markers = spec.to_s.scan(/"x-forge-circular"\s*=>\s*"([^"]+)"/).flatten.uniq
    expect(markers).to include('#/components/schemas/A -> #/components/schemas/B -> #/components/schemas/A')
  end

  it 'decodes percent-encoded pointers (#/paths/~1split~1%7Bid%7D)' do
    spec = { 'paths' => { '/split/{id}' => { 'x' => 1 } }, 'a' => { '$ref' => '#/paths/~1split~1%7Bid%7D' } }
    expect(Forge::RefResolver.resolve(spec)['a']).to eq('x' => 1)
  end

  it 'does not raise on an external $ref in create (analyzer decides, D-05)' do
    spec = described_class.load(broken('external_ref_in_create.yaml'))
    schema = spec.dig('paths', '/payouts', 'post', 'requestBody', 'content', 'application/json', 'schema')
    expect(schema).to eq('x-forge-unresolved' => 'other.yaml#/components/schemas/PayoutRequest')
  end

  it 'raises SpecError with file not found' do
    expect { described_class.load('nope.yaml') }.to raise_error(Forge::SpecError, /file not found/)
  end

  context 'with examples/specs/novapay.yaml' do
    subject(:spec) { described_class.load('examples/specs/novapay.yaml') }

    def refs(node)
      case node
      when Hash then node.key?('$ref') ? [node] : node.values.flat_map { |v| refs(v) }
      when Array then node.flat_map { |v| refs(v) }
      else []
      end
    end

    it 'has no $ref left anywhere' do
      expect(refs(spec)).to be_empty
    end

    it 'marks resolved schemas with x-forge-ref-name' do
      recipient = spec.dig('components', 'schemas', 'CreatePayoutRequest', 'properties', 'recipient')
      expect(recipient['x-forge-ref-name']).to eq('Recipient')
    end
  end

  it 'substitutes server variables (swiftpay.json)' do
    spec = described_class.load('examples/specs/swiftpay.json')
    expect(spec['servers'][0]['url']).to eq('https://sandbox.swiftpay.example/api')
  end

  it 'loads cardpay.yaml' do
    expect(described_class.load('examples/specs/cardpay.yaml')['openapi']).to start_with('3.')
  end

  it 'falls back to JSON for unknown extensions' do
    path = 'tmp/spec.txt'
    File.write(path, '{"openapi":"3.1.0","paths":{"/a":{}}}')
    expect(described_class.load(path)['openapi']).to eq('3.1.0')
  end
end
