# frozen_string_literal: true

require_relative 'forge/version'
require_relative 'forge/errors'
require_relative 'forge/loader'
%w[schema server security_scheme parameter request_body response endpoint spec builder].each do |f|
  require_relative "forge/ir/#{f}"
end
require_relative 'forge/rules'
require_relative 'forge/analyzers/endpoint_roles'
require_relative 'forge/analyzers/auth'
require_relative 'forge/analyzers/statuses'
require_relative 'forge/analyzers/errors'
