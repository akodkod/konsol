# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Notifications
      # Exit notification has no params
      class ExitParams < T::Struct
        extend T::Sig

        sig { params(_params: T.nilable(T::Hash[String, T.untyped])).returns(ExitParams) }
        def self.from_hash(_params)
          new
        end
      end
    end
  end
end
