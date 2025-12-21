# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Requests
      class EvalParams < T::Struct
        extend T::Sig

        const :session_id, String
        const :code, String

        sig { params(params: T.nilable(T::Hash[String, T.untyped])).returns(EvalParams) }
        def self.from_hash(params)
          raise ArgumentError, "Eval request requires sessionId parameter" if params.nil? || params["sessionId"].nil?
          raise ArgumentError, "Eval request requires code parameter" if params["code"].nil?

          new(
            session_id: params["sessionId"],
            code: params["code"],
          )
        end
      end
    end
  end
end
