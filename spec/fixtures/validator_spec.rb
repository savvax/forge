# frozen_string_literal: true

RSpec.describe Forge::Fixtures::Validator do
  let(:schema) do
    Forge::IR::Schema.from('type' => 'object', 'required' => %w[amount currency],
                           'properties' => { 'amount' => { 'type' => 'integer' },
                                             'currency' => { 'type' => 'string', 'enum' => %w[RUB] },
                                             'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
                                             'ok' => { 'type' => 'boolean' } })
  end

  it 'accepts a matching example' do
    expect(described_class.check({ 'amount' => 1, 'currency' => 'RUB', 'tags' => ['a'], 'ok' => true },
                                 schema)).to eq([])
  end

  it 'reports type, enum, required and array mismatches with paths' do
    errors = described_class.check({ 'amount' => '1', 'currency' => 'USD', 'tags' => 'x' }, schema, 'req')
    expect(errors).to contain_exactly('req.amount: expected integer, got String',
                                      "req.currency: 'USD' is not in enum RUB", 'req.tags: expected array, got String')
    expect(described_class.check({ 'amount' => 1 }, schema)).to eq(['value.currency: required field missing'])
    expect(described_class.check('x', schema)).to eq(['value: expected object, got String'])
  end

  it 'ignores nil values and unknown schemas' do
    expect(described_class.check(nil, schema)).to eq([])
    expect(described_class.check({ 'amount' => 1, 'currency' => 'RUB' }, nil)).to eq([])
  end
end
