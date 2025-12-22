# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    class Method < T::Enum
      extend T::Sig

      enums do
        # LSP-like lifecycle methods
        Initialize = new("initialize")
        Shutdown = new("shutdown")
        Exit = new("exit")
        CancelRequest = new("$/cancelRequest")

        # Konsol main methods
        SessionCreate = new("konsol/session.create")
        Eval = new("konsol/eval")
        Interrupt = new("konsol/interrupt")

        # Server notifications (future use)
        Stdout = new("konsol/stdout")
        Stderr = new("konsol/stderr")
        Status = new("konsol/status")
      end

      sig { returns(String) }
      def method_name
        serialize
      end

      sig { params(name: String).returns(T.nilable(Method)) }
      def self.from_name(name)
        values.find { |m| m.method_name == name }
      end

      sig { returns(T::Boolean) }
      def notification?
        case self
        when Exit, Stdout, Stderr, Status then true
        else false
        end
      end
    end
  end
end
