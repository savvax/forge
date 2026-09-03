# frozen_string_literal: true

module Forge
  module IR
    # source: :paths | :callbacks | :webhooks; security: nil (унаследовано) | [] | [{name => scopes}]
    # rubocop:disable-next Lint/DataDefineOverride -- `method` задан docs/ARCHITECTURE.md (HTTP-verb)
    Endpoint = Data.define(:operation_id, :method, :path, :summary, :description, :tags, :parameters,
                           :request_body, :responses, :security, :callbacks, :pointer, :source)
  end
end
