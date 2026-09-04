# frozen_string_literal: true

RSpec.describe Forge::Fixtures::Synthesizer do
  def schema(hash) = Forge::IR::Schema.from(hash)

  it 'is deterministic and prefers examples and enums' do
    s = schema('type' => 'object', 'properties' => { 'a' => { 'type' => 'string', 'example' => 'x' },
                                                     'b' => { 'type' => 'string', 'enum' => %w[p q] },
                                                     'c' => { 'type' => 'integer' }, 'd' => { 'type' => 'boolean' } })
    expect(described_class.example(s)).to eq('a' => 'x', 'b' => 'p', 'c' => 1, 'd' => true)
  end

  it 'handles formats, patterns, arrays and nested objects' do
    s = schema('type' => 'object', 'properties' => {
                 'phone' => { 'type' => 'string', 'pattern' => '^7\d{10}$' },
                 'at' => { 'type' => 'string', 'format' => 'date-time' },
                 'iban' => { 'type' => 'string', 'pattern' => '^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$' },
                 'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
                 'money' => { 'type' => 'object',
                              'properties' => { 'value' => { 'type' => 'number', 'minimum' => 5 } } }
               })
    expect(described_class.example(s)).to eq('phone' => '79000000000', 'at' => '2026-01-01T00:00:00Z',
                                             'iban' => "AA00#{'A' * 11}", 'tags' => ['tags_example'],
                                             'money' => { 'value' => 5 })
  end

  it 'falls back to <name>_example and nil for missing schema' do
    expect(described_class.example(schema('type' => 'string'), 'code')).to eq('code_example')
    expect(described_class.example(nil)).to be_nil
  end
end
