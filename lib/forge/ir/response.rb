# frozen_string_literal: true

module Forge
  module IR
    Response = Data.define(:status, :description, :media_type, :schema, :examples, :headers)
  end
end
