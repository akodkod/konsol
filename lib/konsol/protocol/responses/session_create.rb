# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Responses
      class SessionCreateResult < T::Struct
        extend T::Sig

        const :session_id, String

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "sessionId" => session_id }
        end
      end
    end
  end
end
