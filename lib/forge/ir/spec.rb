# frozen_string_literal: true

module Forge
  module IR
    Spec = Data.define(:title, :version, :openapi_version, :description, :servers, :security_schemes,
                       :default_security, :endpoints, :webhooks, :schemas, :source_path)
  end
end
