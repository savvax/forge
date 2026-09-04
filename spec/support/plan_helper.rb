# frozen_string_literal: true

# План из файла спеки (для рендереров и golden).
module PlanHelper
  def plan_for(file, overrides: nil, provider: nil)
    spec = Forge::IR::Builder.build(Forge::Loader.load(file), source_path: file)
    findings = Forge::Analyzers::Runner.run(spec, rules: Forge::Rules.load, overrides: overrides)
    Forge::Plan::Builder.build(spec, findings, overrides: overrides, provider_name: provider)
  end

  def plan_for_hash(hash, provider: nil)
    spec = ir_for(hash)
    findings = Forge::Analyzers::Runner.run(spec, rules: Forge::Rules.load)
    Forge::Plan::Builder.build(spec, findings, provider_name: provider)
  end
end

RSpec.configure { |c| c.include PlanHelper }
