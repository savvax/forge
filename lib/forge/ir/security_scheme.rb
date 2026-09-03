# frozen_string_literal: true

module Forge
  module IR
    SecurityScheme = Data.define(:name, :type, :location, :param_name, :scheme, :bearer_format, :description)
  end
end
