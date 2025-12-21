# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Requests
      class CancelParams < T::Struct
        extend T::Sig

        const :id, T.any(String, Integer)

        sig { params(params: T.nilable(T::Hash[String, T.untyped])).returns(CancelParams) }
        def self.from_hash(params)
          raise ArgumentError, "Cancel request requires id parameter" if params.nil? || params["id"].nil?

          new(id: params["id"])
        end
      end
    end
  end
end
