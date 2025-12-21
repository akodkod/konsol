# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Notifications
      class StatusParams < T::Struct
        extend T::Sig

        const :session_id, String
        const :busy, T::Boolean

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          {
            "sessionId" => session_id,
            "busy" => busy,
          }
        end
      end
    end
  end
end
