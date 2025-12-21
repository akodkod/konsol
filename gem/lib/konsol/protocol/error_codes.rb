# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    class ErrorCode < T::Enum
      extend T::Sig

      enums do
        # Standard JSON-RPC error codes
        ParseError = new(-32_700)
        InvalidRequest = new(-32_600)
        MethodNotFound = new(-32_601)
        InvalidParams = new(-32_602)
        InternalError = new(-32_603)

        # Konsol-specific error codes
        SessionNotFound = new(-32_001)
        SessionBusy = new(-32_002)
        RailsBootFailed = new(-32_003)
        EvalTimeout = new(-32_004)
        ServerShuttingDown = new(-32_005)
      end

      MESSAGES = T.let(
        {
          -32_700 => "Invalid JSON",
          -32_600 => "Not a valid request object",
          -32_601 => "Method does not exist",
          -32_602 => "Invalid method parameters",
          -32_603 => "Internal server error",
          -32_001 => "Session ID does not exist",
          -32_002 => "Session is currently evaluating",
          -32_003 => "Failed to boot Rails environment",
          -32_004 => "Evaluation timed out",
          -32_005 => "Server is shutting down",
        }.freeze,
        T::Hash[Integer, String],
      )

      sig { returns(Integer) }
      def code
        serialize
      end

      sig { returns(String) }
      def message
        MESSAGES.fetch(code)
      end
    end
  end
end
