# frozen_string_literal: true

module Provider
  Result = Data.define(:status, :code, :data) do
    def success?
      status == :ok
    end

    def failed?
      !success?
    end
  end
end
