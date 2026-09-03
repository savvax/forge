# frozen_string_literal: true

RSpec.describe Forge::Rules do
  subject(:rules) { described_class.load }

  it 'loads thresholds and endpoint roles, frozen' do
    expect(rules.thresholds).to eq('accept' => 0.8, 'warn' => 0.5)
    expect(rules.fetch(:endpoint_roles)['roles'].keys).to eq(%w[create status cancel webhook balance])
    expect(rules.fetch(:endpoint_roles)).to be_frozen
  end

  it 'raises GenerationError for a missing dictionary' do
    expect { rules.fetch(:nope) }.to raise_error(Forge::GenerationError, %r{rules/nope\.yml})
  end

  it 'raises GenerationError for a missing rules dir' do
    expect { described_class.load('spec/nope') }.to raise_error(Forge::GenerationError, %r{spec/nope})
  end

  describe '.normalize' do
    it 'converts camelCase, dashes, dots and spaces to snake_case' do
      expect(described_class.normalize('approvalPending')).to eq('approval_pending')
      expect(described_class.normalize('transfer-orders')).to eq('transfer_orders')
      expect(described_class.normalize('payout.completed')).to eq('payout_completed')
      expect(described_class.normalize('X-NovaPay-Signature')).to eq('x_nova_pay_signature')
    end
  end
end
