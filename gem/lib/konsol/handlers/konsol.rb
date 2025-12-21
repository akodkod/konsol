# typed: strict
# frozen_string_literal: true

module Konsol
  module Handlers
    class Konsol
      extend T::Sig

      sig { params(session_manager: Session::Manager).void }
      def initialize(session_manager:)
        @session_manager = session_manager
        @evaluator = T.let(Session::Evaluator.new, Session::Evaluator)
      end

      sig { returns(Protocol::Responses::SessionCreateResult) }
      def handle_session_create
        session = @session_manager.create_session
        Protocol::Responses::SessionCreateResult.new(session_id: session.id)
      end

      sig { params(params: Protocol::Requests::EvalParams).returns(Protocol::Responses::EvalResult) }
      def handle_eval(params)
        session = @session_manager.get_session!(params.session_id)

        raise SessionBusyError, "Session is busy" if session.busy?

        session.mark_busy!
        begin
          result = @evaluator.evaluate(params.code, session.session_binding)
          result.to_protocol
        ensure
          session.mark_idle!
        end
      end

      sig { params(params: Protocol::Requests::InterruptParams).returns(Protocol::Responses::InterruptResult) }
      def handle_interrupt(params)
        # v1: Stub that returns success but doesn't actually interrupt
        session = @session_manager.get_session!(params.session_id)
        session.mark_interrupted! if session.busy?
        Protocol::Responses::InterruptResult.new(success: true)
      end
    end

    class SessionBusyError < ::Konsol::Error; end
  end
end
