# frozen_string_literal: true

module Forge
  module IR
    RequestBody = Data.define(:required, :media_type, :media_types, :schema, :examples)
  end
end
