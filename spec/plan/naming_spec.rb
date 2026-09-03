# frozen_string_literal: true

RSpec.describe Forge::Plan::Naming do
  it 'derives names from an explicit provider' do
    n = described_class.from_provider('Nova Pay')
    expect(n).to eq(name: 'nova_pay', class_name: 'NovaPayService', env_prefix: 'NOVA_PAY',
                    file_name: 'nova_pay_service.rb', title: 'Nova Pay')
  end

  it 'derives names from a spec title by dropping stop words' do
    expect(described_class.from_title('NovaPay Payout API')[:name]).to eq('novapay')
    expect(described_class.from_title('CardPay Transfers API')[:name]).to eq('cardpay')
    expect(described_class.from_title('SwiftPay Outbound Payments')[:name]).to eq('swiftpay')
    expect(described_class.from_title('Acme REST API v2')).to include(name: 'acme', class_name: 'AcmeService')
  end

  it 'falls back to provider when the title is only stop words' do
    expect(described_class.from_title('Payout API')[:name]).to eq('provider')
  end
end
