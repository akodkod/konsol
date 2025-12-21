# typed: strict
# frozen_string_literal: true

module Konsol
  module Handlers
    class Lifecycle
      extend T::Sig

      sig { params(session_manager: Session::Manager).void }
      def initialize(session_manager:)
        @session_manager = session_manager
        @initialized = T.let(false, T::Boolean)
        @shutdown_requested = T.let(false, T::Boolean)
      end

      sig { returns(T::Boolean) }
      def initialized?
        @initialized
      end

      sig { returns(T::Boolean) }
      def shutdown_requested?
        @shutdown_requested
      end

      sig do
        params(params: Protocol::Requests::InitializeParams)
          .returns(Protocol::Responses::InitializeResult)
      end
      def handle_initialize(params)
        _ = params # Unused for now, but available for future use (e.g., client info logging)
        @initialized = true
        Protocol::Responses::InitializeResult.default
      end

      sig { returns(NilClass) }
      def handle_shutdown
        @shutdown_requested = true
        @session_manager.invalidate_all
        nil
      end

      sig { returns(Integer) }
      def handle_exit
        @shutdown_requested ? 0 : 1
      end

      sig { params(params: Protocol::Requests::CancelParams).returns(T::Boolean) }
      def handle_cancel(params) # rubocop:disable Naming/PredicateMethod
        # v1: Stub that does nothing but returns success
        _ = params
        true
      end
    end
  end
end
