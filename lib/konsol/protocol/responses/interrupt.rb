# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Responses
      class InterruptResult < T::Struct
        extend T::Sig

        const :success, T::Boolean

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          { "success" => success }
        end
      end
    end
  end
end
