# frozen_string_literal: true

# SimpleCov должен стартовать до загрузки lib/ — иначе покрытие не считается.
require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter %w[/spec/ /output/ /tmp/ /examples/ /bin/]
  add_group 'Loader', 'lib/forge/loader'
  add_group 'IR', 'lib/forge/ir'
  add_group 'Analyzers', 'lib/forge/analyzers'
  add_group 'Plan', 'lib/forge/plan'
  add_group 'Renderers', 'lib/forge/renderers'
  add_group 'Provider stub', 'lib/provider'
  unless ENV['REAL'] # spec/real_specs_spec.rb гоняет CLI как подпроцесс — покрытие не считается
    minimum_coverage line: 90, branch: 75
    minimum_coverage_by_file 70
  end
end

require 'webmock/rspec'
require 'forge'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |c| c.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = 'tmp/rspec_examples.txt'
  config.filter_run_when_matching :focus
  config.filter_run_excluding real: true unless ENV['REAL']
  config.order = :defined
  config.warnings = false

  WebMock.disable_net_connect!(allow_localhost: true)

  config.before(:suite) { FileUtils.mkdir_p('tmp') }
end
