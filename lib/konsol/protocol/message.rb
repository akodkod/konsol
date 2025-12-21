# typed: strict
# frozen_string_literal: true

module Konsol
  module Protocol
    # JSON-RPC request ID can be string, integer, or null
    RequestId = T.type_alias { T.nilable(T.any(String, Integer)) }

    # Error data structure for JSON-RPC error responses
    class ErrorData < T::Struct
      extend T::Sig

      const :code, Integer
      const :message, String
      const :data, T.nilable(T::Hash[String, T.untyped]), default: nil

      sig { params(error_code: ErrorCode, data: T.nilable(T::Hash[String, T.untyped])).returns(ErrorData) }
      def self.from_code(error_code, data: nil)
        new(code: error_code.code, message: error_code.message, data: data)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        result = { "code" => code, "message" => message }
        result["data"] = data if data
        result
      end
    end

    # Base JSON-RPC request structure
    class Request < T::Struct
      extend T::Sig

      const :jsonrpc, String, default: "2.0"
      const :id, RequestId
      const :method_name, String
      const :params, T.nilable(T::Hash[String, T.untyped]), default: nil

      sig { params(raw: T::Hash[String, T.untyped]).returns(Request) }
      def self.from_hash(raw)
        new(
          jsonrpc: raw["jsonrpc"] || "2.0",
          id: raw["id"],
          method_name: raw["method"],
          params: raw["params"],
        )
      end
    end

    # JSON-RPC result type - can be any valid JSON value
    ResultType = T.type_alias do
      T.nilable(
        T.any(T::Hash[String, T.untyped], T::Array[T.untyped], String, Integer, Float, T::Boolean),
      )
    end

    # Base JSON-RPC response structure
    class Response < T::Struct
      extend T::Sig

      const :jsonrpc, String, default: "2.0"
      const :id, RequestId
      const :result, T.untyped, default: nil # rubocop:disable Sorbet/ForbidUntypedStructProps
      const :error, T.nilable(ErrorData), default: nil

      sig { params(id: RequestId, result: T.untyped).returns(Response) }
      def self.success(id, result)
        new(id: id, result: result)
      end

      sig { params(id: RequestId, error: ErrorData).returns(Response) }
      def self.error(id, error)
        new(id: id, error: error)
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        result_hash = { "jsonrpc" => jsonrpc, "id" => id }
        if error
          result_hash["error"] = error.to_h
        else
          result_hash["result"] = result
        end
        result_hash
      end
    end

    # Base JSON-RPC notification structure (no id, no response expected)
    class Notification < T::Struct
      extend T::Sig

      const :jsonrpc, String, default: "2.0"
      const :method_name, String
      const :params, T.nilable(T::Hash[String, T.untyped]), default: nil

      sig { params(raw: T::Hash[String, T.untyped]).returns(Notification) }
      def self.from_hash(raw)
        new(
          jsonrpc: raw["jsonrpc"] || "2.0",
          method_name: raw["method"],
          params: raw["params"],
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def to_h
        result = { "jsonrpc" => jsonrpc, "method" => method_name }
        result["params"] = params if params
        result
      end
    end
  end
end
