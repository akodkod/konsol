# typed: strict
# frozen_string_literal: true

module Konsol
  class Server
    extend T::Sig

    sig { params(input: T.any(IO, StringIO), output: T.any(IO, StringIO)).void }
    def initialize(input: $stdin, output: $stdout)
      @input = input
      @output = output
      @reader = T.let(Framing::Reader.new(input), Framing::Reader)
      @writer = T.let(Framing::Writer.new(output), Framing::Writer)
      @session_manager = T.let(Session::Manager.new, Session::Manager)
      @lifecycle = T.let(Handlers::Lifecycle.new(session_manager: @session_manager), Handlers::Lifecycle)
      @konsol = T.let(Handlers::Konsol.new(session_manager: @session_manager), Handlers::Konsol)
      @shutdown_requested = T.let(false, T::Boolean)
    end

    sig { returns(Integer) }
    def run
      setup_signal_handlers

      loop do
        break if @shutdown_requested

        message = @reader.read
        break if message.nil?

        process_message(message)
      end

      @lifecycle.handle_exit
    end

    private

    sig { void }
    def setup_signal_handlers
      Signal.trap("INT") { @shutdown_requested = true }
      Signal.trap("TERM") { @shutdown_requested = true }
    end

    # rubocop:disable Metrics/AbcSize
    sig { params(message: T::Hash[String, T.untyped]).void }
    def process_message(message)
      # Check if it's a notification (no id)
      if message["id"].nil?
        process_notification(message)
        return
      end

      request = Protocol::Request.from_hash(message)
      response = handle_request(request)

      send_response(response) if response
    rescue Framing::Reader::ParseError => e
      send_error_response(message["id"], Protocol::ErrorCode::ParseError, e.message)
    rescue ArgumentError => e
      send_error_response(message["id"], Protocol::ErrorCode::InvalidParams, e.message)
    rescue Session::SessionNotFoundError => e
      send_error_response(message["id"], Protocol::ErrorCode::SessionNotFound, e.message)
    rescue Session::RailsBootError => e
      send_error_response(message["id"], Protocol::ErrorCode::RailsBootFailed, e.message)
    rescue Handlers::SessionBusyError => e
      send_error_response(message["id"], Protocol::ErrorCode::SessionBusy, e.message)
    rescue StandardError => e
      send_error_response(message["id"], Protocol::ErrorCode::InternalError, e.message)
    end
    # rubocop:enable Metrics/AbcSize

    sig { params(notification: T::Hash[String, T.untyped]).void }
    def process_notification(notification)
      method_name = notification["method"]

      case method_name
      when "exit"
        @shutdown_requested = true
      end
      # Other notifications are ignored in v1
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    sig { params(request: Protocol::Request).returns(T.nilable(Protocol::Response)) }
    def handle_request(request)
      method = Protocol::Method.from_name(request.method_name)

      unless method
        return Protocol::Response.error(
          request.id,
          Protocol::ErrorData.from_code(Protocol::ErrorCode::MethodNotFound),
        )
      end

      result = case method
               when Protocol::Method::Initialize
                 params = Protocol::Requests::InitializeParams.from_hash(request.params)
                 @lifecycle.handle_initialize(params).to_h
               when Protocol::Method::Shutdown
                 @lifecycle.handle_shutdown
               when Protocol::Method::CancelRequest
                 params = Protocol::Requests::CancelParams.from_hash(request.params)
                 @lifecycle.handle_cancel(params)
               when Protocol::Method::SessionCreate
                 @konsol.handle_session_create.to_h
               when Protocol::Method::Eval
                 params = Protocol::Requests::EvalParams.from_hash(request.params)
                 @konsol.handle_eval(params).to_h
               when Protocol::Method::Interrupt
                 params = Protocol::Requests::InterruptParams.from_hash(request.params)
                 @konsol.handle_interrupt(params).to_h
               else
                 return Protocol::Response.error(
                   request.id,
                   Protocol::ErrorData.from_code(Protocol::ErrorCode::MethodNotFound),
                 )
               end

      Protocol::Response.success(request.id, result)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    sig { params(response: Protocol::Response).void }
    def send_response(response)
      @writer.write(Util::CaseTransform.to_camel_case(response.to_h))
    end

    sig do
      params(
        id: Protocol::RequestId,
        error_code: Protocol::ErrorCode,
        message: String,
      ).void
    end
    def send_error_response(id, error_code, message)
      error = Protocol::ErrorData.new(code: error_code.code, message: message)
      response = Protocol::Response.error(id, error)
      send_response(response)
    end
  end
end
