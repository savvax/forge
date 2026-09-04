# frozen_string_literal: true

require 'open3'

RSpec.describe 'bin/e2e' do
  %w[examples/specs/novapay.yaml examples/specs/cardpay.yaml].each do |spec_file|
    it "approves an operation end-to-end for #{File.basename(spec_file)}" do
      out, status = Open3.capture2e(File.expand_path('bin/e2e'), spec_file)
      expect(status.exitstatus).to eq(0), out
      expect(out).to include('check_conditions ok', 'webhook received', 'operation approved ✓')
    end
  end
end
