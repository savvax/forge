# frozen_string_literal: true

require 'fileutils'
require 'forge/generate_command'

RSpec.describe Forge::GenerateCommand do
  let(:out) { 'tmp/generate_command_spec' }
  let(:base) do
    { spec: 'examples/specs/novapay.yaml', out: out, include_paths: [], force: true, verify: false, format: 'text' }
  end

  before { FileUtils.rm_rf(out) }

  it 'runs the pipeline, writes report.txt with local paths and returns 0' do
    expect { expect(described_class.new(base).run).to eq(0) }.to output(/Done: 7 files, 3 warnings/).to_stdout
    report = File.read("#{out}/report.txt")
    expect(report).to include('  ./novapay_service.rb', 'Verifying generated code... ok (ruby -c ×4, rspec skipped')
    expect(report).not_to include(out)
  end

  it 'returns 4 with strict and prints json when asked' do
    expect { expect(described_class.new(base.merge(strict: true, format: 'json')).run).to eq(4) }
      .to output(/"exit_code": 4/).to_stdout
  end

  it 'renders the mock files for bin/forge mock' do
    plan, dir = described_class.new(base.merge(out: 'tmp/mock_cmd')).render_mock
    expect(plan.provider[:name]).to eq('novapay')
    expect(File).to exist("#{dir}/mock_server.rb")
  end

  it 'applies overrides and provider name' do
    opts = base.merge(spec: 'examples/specs/cardpay.yaml', overrides: 'examples/overrides/cardpay.yml',
                      provider: 'Card Pay', strict: true)
    expect { expect(described_class.new(opts).run).to eq(0) }.to output(/0 warnings/).to_stdout
    expect(File).to exist("#{out}/card_pay_service.rb")
  end
end
