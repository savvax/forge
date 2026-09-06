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

  it 'approves cardpay with its overrides (all WARN closed)' do
    out, status = e2e('examples/specs/cardpay.yaml', '--overrides', 'examples/overrides/cardpay.yml')
    expect(status.exitstatus).to eq(0), out
    expect(out).to include('operation approved ✓')
  end

  it 'fails cleanly for swiftpay: the timestamped signature scheme is UNSUPPORTED, no stack trace' do
    out, status = e2e('examples/specs/swiftpay.json')
    expect(status.exitstatus).to eq(1)
    expect(out).to include('webhook received', 'process_callback: signature_unsupported')
    expect(out).not_to include('NotImplementedError', 'from bin/e2e')
  end
end
