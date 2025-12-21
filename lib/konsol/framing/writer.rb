# typed: strict
# frozen_string_literal: true

require "json"
require "stringio"

module Konsol
  module Framing
    class Writer
      extend T::Sig

      sig { params(io: T.any(IO, StringIO)).void }
      def initialize(io)
        @io = io
      end

      # Writes a JSON-RPC message with Content-Length header
      sig { params(message: T::Hash[String, T.untyped]).void }
      def write(message)
        payload = JSON.generate(message)
        content_length = payload.bytesize

        @io.write("Content-Length: #{content_length}\r\n")
        @io.write("\r\n")
        @io.write(payload)
        @io.flush
      end
    end
  end
end
