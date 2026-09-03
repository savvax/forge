# frozen_string_literal: true

module Forge
  module IR
    Parameter = Data.define(:name, :location, :required, :schema, :description, :example)
  end
end
