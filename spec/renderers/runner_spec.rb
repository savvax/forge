# frozen_string_literal: true

require 'fileutils'

RSpec.describe Forge::Renderers::Runner do
  let(:plan) { plan_for('examples/specs/novapay.yaml') }
  let(:out) { 'tmp/runner_spec' }

  before { FileUtils.rm_rf(out) }

  it 'renders all files in the task order and copies the helper' do
    files = described_class.render(plan, out_dir: out)
    expect(files.map { |f| f[:label] }).to eq(['service', 'integration guide', 'test fixtures', 'service spec'])
    expect(Dir.children(out).sort).to eq(%w[INTEGRATION.md fixtures.json generated_spec_helper.rb novapay_service.rb
                                            novapay_service_spec.rb])
  end

  it 'refuses a non-empty directory without force and overwrites with it' do
    described_class.render(plan, out_dir: out)
    expect { described_class.render(plan, out_dir: out) }.to raise_error(Forge::GenerationError, /not empty.*--force/m)
    expect(described_class.render(plan, out_dir: out, force: true).size).to eq(4)
  end
end
