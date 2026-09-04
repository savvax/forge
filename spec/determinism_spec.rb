# frozen_string_literal: true

require 'digest'
require 'fileutils'

RSpec.describe 'determinism' do
  it 'generates byte-identical output twice' do
    sums = [1, 2].map do |run|
      dir = "tmp/determinism_spec/#{run}"
      FileUtils.rm_rf(dir)
      result = run_cli('generate', '--spec', 'examples/specs/novapay.yaml', '--out', dir, '--force', '--no-verify')
      raise result.output unless result.exit_code.zero?

      Dir["#{dir}/*"].to_h { |f| [File.basename(f), Digest::SHA256.file(f).hexdigest] }
    end
    expect(sums[0]).to eq(sums[1])
    expect(sums[0].keys).to include('novapay_service.rb', 'report.txt', 'fixtures.json')
  end
end
