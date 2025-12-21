# typed: strict
# frozen_string_literal: true

require "securerandom"

module Konsol
  module Session
    class State < T::Enum
      enums do
        Idle = new
        Busy = new
        Interrupted = new
      end
    end

    class Session
      extend T::Sig

      sig { returns(String) }
      attr_reader :id

      sig { returns(Binding) }
      attr_reader :session_binding

      sig { returns(State) }
      attr_reader :state

      sig { void }
      def initialize
        @id = T.let(SecureRandom.uuid, String)
        @session_binding = T.let(create_binding, Binding)
        @state = T.let(State::Idle, State)
      end

      sig { returns(T::Boolean) }
      def idle?
        @state == State::Idle
      end

      sig { returns(T::Boolean) }
      def busy?
        @state == State::Busy
      end

      sig { void }
      def mark_busy!
        @state = State::Busy
      end

      sig { void }
      def mark_idle!
        @state = State::Idle
      end

      sig { void }
      def mark_interrupted!
        @state = State::Interrupted
      end

      private

      sig { returns(Binding) }
      def create_binding
        context = Object.new

        # Add Rails console helpers if available
        context.extend(Rails::ConsoleMethods) if defined?(Rails::ConsoleMethods)

        context.instance_eval { binding }
      end
    end
  end
end
