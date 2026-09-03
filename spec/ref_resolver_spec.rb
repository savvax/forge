# frozen_string_literal: true

RSpec.describe Forge::RefResolver do
  it 'resolves a pointer with ~1 escapes' do
    spec = {
      'paths' => { '/transfer' => { 'post' => { 'requestBody' => { 'x' => 1 } } } },
      'components' => { 'requestBodies' => { 'T' => { '$ref' => '#/paths/~1transfer/post/requestBody' } } }
    }
    expect(described_class.resolve(spec).dig('components', 'requestBodies', 'T')).to eq('x' => 1)
  end

  it 'resolves ~0 as a tilde' do
    spec = { 'a~b' => { 'v' => 2 }, 'c' => { '$ref' => '#/a~0b' } }
    expect(described_class.resolve(spec)['c']).to eq('v' => 2)
  end

  it 'adds x-forge-ref-name only for component schemas' do
    spec = { 'components' => { 'schemas' => { 'S' => { 'type' => 'object' } },
                               'parameters' => { 'P' => { 'name' => 'p' } } },
             'a' => { '$ref' => '#/components/schemas/S' }, 'b' => { '$ref' => '#/components/parameters/P' } }
    out = described_class.resolve(spec)
    expect(out['a']).to eq('type' => 'object', 'x-forge-ref-name' => 'S')
    expect(out['b']).to eq('name' => 'p')
  end

  it 'leaves external refs outside create as x-forge-unresolved' do
    spec = { 'paths' => { '/balance' => { 'get' => { 'responses' => {
      '200' => { 'content' => { 'application/json' => { 'schema' => { '$ref' => 'http://x/schema.json#/B' } } } }
    } } } } }
    out = described_class.resolve(spec)
    schema = out.dig('paths', '/balance', 'get', 'responses', '200', 'content', 'application/json', 'schema')
    expect(schema).to eq('x-forge-unresolved' => 'http://x/schema.json#/B')
  end

  it 'reports an unresolved local ref with pointer and file' do
    expect { described_class.resolve({ 'a' => { '$ref' => '#/nope' } }, file: 'f.yaml') }
      .to raise_error(Forge::SpecError) { |e| expect(e.message).to include('unresolved $ref', '#/a', 'f.yaml') }
  end

  it 'allows a self-referencing schema through a sibling (no false cycle)' do
    spec = { 'components' => { 'schemas' => { 'S' => { 'type' => 'object' } } },
             'a' => { '$ref' => '#/components/schemas/S' }, 'b' => { '$ref' => '#/components/schemas/S' } }
    out = described_class.resolve(spec)
    expect(out['a']).to eq(out['b'])
  end
end
