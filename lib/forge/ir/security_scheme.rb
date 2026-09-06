# frozen_string_literal: true

module Forge
  module IR
    # token_url — только для oauth2 с clientCredentials (flows.clientCredentials.tokenUrl); иначе nil.
    SecurityScheme = Data.define(:name, :type, :location, :param_name, :scheme, :bearer_format, :description,
                                 :token_url)
  end
end
