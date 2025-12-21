# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Requests
      # Shutdown request has no params
      class ShutdownParams < T::Struct
        extend T::Sig

        sig { params(_params: T.nilable(T::Hash[String, T.untyped])).returns(ShutdownParams) }
        def self.from_hash(_params)
          new
        end
      end
    end
  end
end
