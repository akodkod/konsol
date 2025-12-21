# typed: strict
# frozen_string_literal: true

require "stringio"

module Konsol
  module Session
    class EvalResult
      extend T::Sig

      sig { returns(String) }
      attr_reader :value

      sig { returns(T.nilable(String)) }
      attr_reader :value_type

      sig { returns(String) }
      attr_reader :stdout

      sig { returns(String) }
      attr_reader :stderr

      sig { returns(T.nilable(ExceptionInfo)) }
      attr_reader :exception

      sig do
        params(
          value: String,
          value_type: T.nilable(String),
          stdout: String,
          stderr: String,
          exception: T.nilable(ExceptionInfo),
        ).void
      end
      def initialize(value:, value_type:, stdout:, stderr:, exception:)
        @value = value
        @value_type = value_type
        @stdout = stdout
        @stderr = stderr
        @exception = exception
      end

      sig { returns(Protocol::Responses::EvalResult) }
      def to_protocol
        Protocol::Responses::EvalResult.new(
          value: value,
          value_type: value_type,
          stdout: stdout,
          stderr: stderr,
          exception: exception&.to_protocol,
        )
      end
    end

    class ExceptionInfo
      extend T::Sig

      sig { returns(String) }
      attr_reader :class_name

      sig { returns(String) }
      attr_reader :message

      sig { returns(T::Array[String]) }
      attr_reader :backtrace

      sig do
        params(
          class_name: String,
          message: String,
          backtrace: T::Array[String],
        ).void
      end
      def initialize(class_name:, message:, backtrace:)
        @class_name = class_name
        @message = message
        @backtrace = backtrace
      end

      sig { returns(Protocol::Responses::ExceptionInfo) }
      def to_protocol
        Protocol::Responses::ExceptionInfo.new(
          class_name: class_name,
          message: message,
          backtrace: backtrace,
        )
      end
    end

    class Evaluator
      extend T::Sig

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      sig { params(code: String, session_binding: Binding).returns(EvalResult) }
      def evaluate(code, session_binding)
        stdout_capture = StringIO.new
        stderr_capture = StringIO.new

        original_stdout = $stdout
        original_stderr = $stderr

        result_value = nil
        result_type = nil
        exception_info = nil

        begin
          $stdout = stdout_capture
          $stderr = stderr_capture

          result_value = with_rails_wrapping do
            # rubocop:disable Security/Eval
            Kernel.eval(code, session_binding, "(konsol)", 1)
            # rubocop:enable Security/Eval
          end
          result_type = result_value.class.name
        rescue Exception => e # rubocop:disable Lint/RescueException
          exception_info = ExceptionInfo.new(
            class_name: e.class.name || "UnknownError",
            message: e.message,
            backtrace: e.backtrace || [],
          )
        ensure
          $stdout = original_stdout
          $stderr = original_stderr
        end

        EvalResult.new(
          value: result_value.inspect,
          value_type: result_type,
          stdout: stdout_capture.string,
          stderr: stderr_capture.string,
          exception: exception_info,
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      sig do
        type_parameters(:T)
          .params(block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def with_rails_wrapping(&block)
        return yield unless defined?(Rails) && Rails.application

        executor = Rails.application.executor if Rails.application.respond_to?(:executor)
        reloader = Rails.application.reloader if Rails.application.respond_to?(:reloader)

        if executor && reloader
          executor.wrap do
            reloader.wrap(&block)
          end
        elsif executor
          executor.wrap(&block)
        else
          yield
        end
      end
    end
  end
end
