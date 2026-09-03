# frozen_string_literal: true

RSpec.describe 'CLI' do
  describe 'bin/forge' do
    it 'prints the version' do
      res = run_cli('version')
      expect(res.stdout.strip).to eq("forge #{Forge::VERSION}")
      expect(res.exit_code).to eq(0)
    end

    it 'lists the four commands in help' do
      res = run_cli('help')
      expect(res.stdout).to include('analyze', 'generate', 'mock', 'version')
      expect(res.exit_code).to eq(0)
    end

    %w[generate mock].each do |cmd|
      it "#{cmd} is not implemented yet (exit 2)" do
        res = run_cli(cmd, '--spec', 'x.yaml')
        expect(res.stderr).to include('not implemented')
        expect(res.exit_code).to eq(2)
      end
    end
  end

  describe 'bin/forge analyze' do
    { 'novapay' => 'examples/specs/novapay.yaml', 'cardpay' => 'examples/specs/cardpay.yaml',
      'swiftpay' => 'examples/specs/swiftpay.json' }.each do |name, file|
      it "matches the snapshot for #{name}" do
        res = run_cli('analyze', '--spec', file)
        snapshot = "spec/snapshots/#{name}_analyze.txt"
        File.write(snapshot, res.stdout) if ENV['UPDATE_SNAPSHOTS']
        expect(res.exit_code).to eq(0)
        expect(res.stdout).to eq(File.read(snapshot))
      end
    end

    it 'prints valid json with --format json' do
      res = run_cli('analyze', '--spec', 'examples/specs/novapay.yaml', '--format', 'json')
      json = JSON.parse(res.stdout)
      expect(json.keys).to eq(%w[spec endpoints auth statuses errors webhook amount fields warnings exit_code])
      expect(json['exit_code']).to eq(0)
    end

    it 'honours --include-paths' do
      res = run_cli('analyze', '--spec', 'examples/specs/novapay.yaml', '--include-paths', '/balance')
      expect(res.stdout).to include('no_create_endpoint')
      expect(res.exit_code).to eq(0)
    end

    broken = Dir['spec/fixtures/broken/*'].reject { |f| f.include?('no_create') || f.include?('external_ref') }
    broken.each do |file|
      it "fails cleanly on #{File.basename(file)}" do
        res = run_cli('analyze', '--spec', file)
        expect(res.exit_code).to eq(1)
        expect(res.stderr).to start_with('error: ')
        expect(res.stderr).to include('hint:', File.basename(file))
        expect(res.stderr).not_to include('.rb:')
      end
    end

    it 'exits 1 on an external ref inside the create request' do
      res = run_cli('analyze', '--spec', 'spec/fixtures/broken/external_ref_in_create.yaml')
      expect(res.exit_code).to eq(1)
      expect(res.stderr).to include('external $ref', 'hint:')
    end

    it 'exits 0 with a WARN when there is no create endpoint' do
      res = run_cli('analyze', '--spec', 'spec/fixtures/broken/no_create.yaml')
      expect(res.exit_code).to eq(0)
      expect(res.stdout).to include('no_create_endpoint')
    end

    it 'reports a missing file' do
      res = run_cli('analyze', '--spec', 'nope.yaml')
      expect(res.stderr).to include('file not found')
      expect(res.exit_code).to eq(1)
    end

    it 'prints a stacktrace with --debug' do
      res = run_cli('analyze', '--spec', 'spec/fixtures/broken/empty.yaml', '--debug')
      expect(res.stderr).to include('.rb:')
      expect(res.exit_code).not_to eq(0)
    end
  end

  describe 'bin/integrate' do
    it 'rejects non-ruby languages' do
      res = run_integrate('--spec', 'x.yaml', '--provider', 'p', '--lang', 'python')
      expect(res.stderr).to include('only ruby is supported')
      expect(res.exit_code).to eq(1)
    end

    it 'delegates to forge generate --out ./output' do
      res = run_integrate('--spec', 'x.yaml', '--provider', 'p')
      expect(res.stderr).to include('not implemented')
      expect(res.exit_code).to eq(2)
    end
  end
end
