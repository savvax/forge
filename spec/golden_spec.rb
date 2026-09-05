# frozen_string_literal: true

require 'fileutils'

# Байт-в-байт сравнение вывода generate с spec/golden/<provider>/ (docs/TESTING.md § 4).
# Обновление: UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb — только после просмотра диффа.
RSpec.describe 'golden output' do
  def generate_golden(name, spec_file, overrides: nil)
    out = "tmp/golden/#{name}"
    FileUtils.rm_rf(out)
    args = ['generate', '--spec', spec_file, '--out', out, '--force', '--no-verify']
    args += ['--overrides', overrides] if overrides
    result = run_cli(*args)
    raise result.output unless result.exit_code.zero?

    update_golden(out, "spec/golden/#{name}") if ENV['UPDATE_GOLDEN']
    out
  end

  def update_golden(out, golden_dir)
    FileUtils.rm_rf(golden_dir)
    FileUtils.cp_r(out, golden_dir)
  end

  def read(path) = File.read(path).gsub("\r\n", "\n")

  {
    'novapay' => ['examples/specs/novapay.yaml', nil],
    'cardpay' => ['examples/specs/cardpay.yaml', nil],
    'cardpay_overrides' => ['examples/specs/cardpay.yaml', 'examples/overrides/cardpay.yml'],
    'swiftpay' => ['examples/specs/swiftpay.json', nil],
    'swiftpay_overrides' => ['examples/specs/swiftpay.json', 'examples/overrides/swiftpay.yml'],
    'raiffeisen' => ['examples/specs/raiffeisen.yaml', nil],
    'raiffeisen_overrides' => ['examples/specs/raiffeisen.yaml', 'examples/overrides/raiffeisen.yml']
  }.each do |name, (spec_file, overrides)|
    it "produces exactly the golden files for #{name}" do
      out = generate_golden(name, spec_file, overrides: overrides)
      golden_dir = "spec/golden/#{name}"
      expect(Dir.children(out).sort).to eq(Dir.children(golden_dir).sort)
      Dir.children(golden_dir).sort.each do |file|
        expect(read("#{out}/#{file}")).to eq(read("#{golden_dir}/#{file}")), "#{file} differs from golden"
      end
    end
  end
end
