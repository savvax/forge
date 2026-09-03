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

    %w[analyze generate mock].each do |cmd|
      it "#{cmd} is not implemented yet (exit 2)" do
        res = run_cli(cmd, '--spec', 'x.yaml')
        expect(res.stderr).to include('not implemented')
        expect(res.exit_code).to eq(2)
      end
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
