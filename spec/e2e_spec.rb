# frozen_string_literal: true

require 'open3'

RSpec.describe 'bin/e2e' do
  def e2e(*args) = Open3.capture2e(File.expand_path('bin/e2e'), *args)

  %w[examples/specs/novapay.yaml examples/specs/cardpay.yaml examples/specs/raiffeisen.yaml].each do |spec_file|
    it "approves an operation end-to-end for #{File.basename(spec_file)}" do
      out, status = e2e(spec_file)
      expect(status.exitstatus).to eq(0), out
      expect(out).to include('check_conditions ok', 'webhook received', 'operation approved ✓')
    end
  end

  it 'approves an oauth2 client_credentials provider: token from the mock, then Bearer on every call' do
    out, status = e2e('spec/fixtures/oauth2_payout.yaml')
    expect(status.exitstatus).to eq(0), out
    expect(out).to include('create_request ok', 'operation approved ✓')
  end

  it 'approves cardpay with its overrides (all WARN closed)' do
    out, status = e2e('examples/specs/cardpay.yaml', '--overrides', 'examples/overrides/cardpay.yml')
    expect(status.exitstatus).to eq(0), out
    expect(out).to include('operation approved ✓')
  end

  it 'prints a Forge error without a stack trace for a missing or broken spec' do
    out, status = e2e('nope.yaml')
    expect(status.exitstatus).to eq(1)
    expect(out).to include('error: file not found')
    expect(out).not_to include('.rb:')
  end

  it 'approves swiftpay: the t=…,v1=… timestamped signature is verified end-to-end' do
    out, status = e2e('examples/specs/swiftpay.json')
    expect(status.exitstatus).to eq(0), out
    expect(out).to include('webhook received', 'operation approved ✓')
  end
end
