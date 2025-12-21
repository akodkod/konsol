# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    module Responses
      class ExceptionInfo < T::Struct
        extend T::Sig

        const :class_name, String
        const :message, String
        const :backtrace, T::Array[String]

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          {
            "class" => class_name,
            "message" => message,
            "backtrace" => backtrace,
          }
        end
      end

      class EvalResult < T::Struct
        extend T::Sig

        const :value, String
        const :value_type, T.nilable(String), default: nil
        const :stdout, String, default: ""
        const :stderr, String, default: ""
        const :exception, T.nilable(ExceptionInfo), default: nil

        sig { returns(T::Hash[String, T.untyped]) }
        def to_h
          result = {
            "value" => value,
            "stdout" => stdout,
            "stderr" => stderr,
          }
          result["valueType"] = value_type if value_type
          result["exception"] = exception.to_h if exception
          result
        end
      end
    end
  end
end
