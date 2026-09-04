# frozen_string_literal: true

require 'timeout'

# Реальные спеки (docs/REAL_SPECS.md): тег :real, запускается `REAL=1` после `rake real:fetch`.
# Снапшот отчёта: examples/real/reports/<name>.txt (обновление REAL_UPDATE=1).
RSpec.describe 'real provider specs', :real do
  # rubocop:disable-next Lint/ConstantDefinitionInBlock, RSpec/LeakyConstantDeclaration
  CASES = {
    'adyen_payout' => { flags: [], exit: 0, roles: { create: 'post-payout' }, auth: 'basic',
                        warns: %w[no_webhook status_field_not_found] },
    'adyen_transfers' => { flags: [], exit: 0, roles: { create: 'post-transfers', status: 'get-transfers-id' },
                           auth: 'api_key', warns: %w[unmapped_status api_key_in_query] },
    'paypal_payouts' => { flags: [], exit: 0, roles: { create: 'payouts.post', status: 'payouts.get' }, auth: 'bearer',
                          warns: %w[array_field_unsupported], unsupported: %w[oauth2] },
    'paystack' => { flags: ['--include-paths', '/transfer*', '--include-paths', '/balance'], exit: 0,
                    roles: { create: 'transfer_initiate', status: 'transfer_fetch', balance: 'balance_fetch' },
                    auth: 'bearer', warns: %w[role_conflict] },
    'stripe' => { flags: ['--include-paths', '/v1/payouts*'], exit: 0,
                  roles: { create: 'PostPayouts', status: 'GetPayoutsPayout', cancel: 'PostPayoutsPayoutCancel' },
                  auth: 'basic', warns: %w[status_from_description no_webhook] },
    'square' => { flags: ['--include-paths', '/v2/payouts*'], exit: 0, roles: { status: 'GetPayout' },
                  warns: %w[no_create_endpoint] },
    'plaid' => { flags: ['--include-paths', '/transfer/*'], exit: 0,
                 roles: { create: 'transferCreate', cancel: 'transferCancel' }, auth: 'api_key', warns: %w[no_webhook] }
  }.freeze

  def spec_file(name) = Dir["examples/real/#{name}.*"].first

  def analyze(name, flags, format: 'text')
    run_cli('analyze', '--spec', spec_file(name), '--format', format, *flags)
  end

  CASES.each do |name, expected|
    describe name do
      before { skip 'run rake real:fetch first' unless spec_file(name) }

      it 'analyzes with the expected exit code, roles and auth' do
        res = Timeout.timeout(60) { analyze(name, expected[:flags], format: 'json') }
        expect(res.exit_code).to eq(expected[:exit]), res.stderr
        json = JSON.parse(res.stdout)
        roles = json['endpoints'].to_h { |e| [e['role'].to_sym, e['operation_id']] }
        expected[:roles].each { |role, op| expect(roles[role]).to eq(op) }
        expect(json.dig('auth', 'type')).to eq(expected[:auth]) if expected[:auth]
        codes = json['warnings'].map { |w| w['code'] }
        expect(codes).to include(*expected.fetch(:warns, []), *expected.fetch(:unsupported, []))
      end

      it 'matches the report snapshot' do
        res = analyze(name, expected[:flags])
        snapshot = "examples/real/reports/#{name}.txt"
        File.write(snapshot, res.stdout) if ENV['REAL_UPDATE'] || !File.exist?(snapshot)
        expect(res.stdout).to eq(File.read(snapshot))
      end
    end
  end

  it 'loads Stripe in under 10 seconds' do
    skip 'run rake real:fetch first' unless spec_file('stripe')
    expect { Timeout.timeout(10) { Forge::Loader.load(spec_file('stripe')) } }.not_to raise_error
  end
end
