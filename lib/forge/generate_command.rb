# frozen_string_literal: true

require_relative 'renderers/runner'
require_relative 'renderers/report_file'

module Forge
  # Конвейер generate: Load → IR → Analyze → Plan → Render → Verify → Report. Возвращает код выхода.
  class GenerateCommand
    STRICT_EXIT = 4

    def self.analyze(opts)
      spec = IR::Builder.build(Loader.load(opts[:spec]), source_path: opts[:spec])
      overrides = opts[:overrides] && Plan::Overrides.load(opts[:overrides])
      findings = Analyzers::Runner.run(spec, rules: Rules.load, include_paths: opts[:include_paths],
                                             overrides: overrides)
      [spec, findings, overrides]
    end

    def initialize(opts)
      @opts = opts
    end

    def run
      spec, findings, overrides = self.class.analyze(@opts)
      plan = Plan::Builder.build(spec, findings, overrides: overrides, provider_name: @opts[:provider])
      files = Renderers::Runner.render(plan, out_dir: @opts[:out], templates_dir: @opts[:templates_dir],
                                             force: @opts[:force])
      generation = { steps: files.map { |f| f[:label] }, verify: verify(files, plan), outputs: outputs(files) }
      text = Report.text(spec, findings, generation: generation)
      Renderers::ReportFile.write(@opts[:out], text)
      print_report(spec, findings, generation, text)
      exit_code(findings)
    end

    private

    def verify(files, plan)
      ruby = files.map { |f| f[:path] }.grep(/\.rb\z/)
      Verifier.syntax!(ruby)
      return "ok (ruby -c ×#{ruby.size}, rspec skipped: --no-verify)" unless @opts[:verify]

      spec_path = File.join(@opts[:out], "#{plan.provider[:name]}_service_spec.rb")
      out = Verifier.spec!(spec_path, load_paths: [File.expand_path('..', __dir__), @opts[:out]])
      "ok (ruby -c ×#{ruby.size}, rspec #{out[/\d+ examples?, \d+ failures?[^\n]*/]})"
    end

    def outputs(files)
      names = files.map { |f| File.basename(f[:path]) } + ['report.txt']
      names.map { |name| "./#{File.join(@opts[:out], name)}".sub(%r{\A\./\./}, './') }
    end

    def print_report(spec, findings, generation, text)
      return puts(text) unless @opts[:format] == 'json'

      puts Report.json(spec, findings, exit_code: exit_code(findings), generation: generation)
    end

    def exit_code(findings)
      return 0 unless @opts[:strict]

      findings.values.flat_map(&:warnings).any? { |w| w.level != :info } ? STRICT_EXIT : 0
    end
  end
end
