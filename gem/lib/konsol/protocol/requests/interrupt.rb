# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Requests
      class InterruptParams < T::Struct
        extend T::Sig

        const :session_id, String

        sig { params(params: T.nilable(T::Hash[String, T.untyped])).returns(InterruptParams) }
        def self.from_hash(params)
          if params.nil? || params["sessionId"].nil?
            raise ArgumentError,
                  "Interrupt request requires sessionId parameter"
          end

          new(session_id: params["sessionId"])
        end
      end
    end
  end
end
