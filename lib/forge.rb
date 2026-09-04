# frozen_string_literal: true

require_relative 'forge/version'
require_relative 'forge/errors'
require_relative 'forge/loader'
%w[schema server security_scheme parameter request_body response endpoint spec builder].each do |f|
  require_relative "forge/ir/#{f}"
end
require_relative 'forge/rules'
require_relative 'forge/plan/overrides'
require_relative 'forge/analyzers/runner'
require_relative 'forge/report'
require_relative 'forge/plan/builder'
