# typed: strict
# frozen_string_literal: true

require "json"
require "stringio"

module Konsol
  module Framing
    class Reader
      extend T::Sig

      class ReadError < Konsol::Error; end
      class ParseError < ReadError; end

      sig { params(io: T.any(IO, StringIO)).void }
      def initialize(io)
        @io = io
      end

      # Reads and parses a single JSON-RPC message from the input stream
      # Returns nil on EOF
      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      def read
        content_length = read_headers
        return nil if content_length.nil?

        payload = read_payload(content_length)
        return nil if payload.nil?

        parse_json(payload)
      end

      private

      sig { returns(T.nilable(Integer)) }
      def read_headers
        content_length = nil

        loop do
          line = @io.gets("\r\n")
          return nil if line.nil? # EOF

          # Empty line signals end of headers
          break if line == "\r\n"

          # Parse Content-Length header
          if (match = line.match(/^Content-Length:\s*(\d+)/i))
            content_length = match[1]&.to_i
          end
          # Ignore other headers
        end

        raise ReadError, "Missing Content-Length header" if content_length.nil?

        content_length
      end

      sig { params(length: Integer).returns(T.nilable(String)) }
      def read_payload(length)
        payload = @io.read(length)
        return nil if payload.nil?

        if payload.bytesize < length
          raise ReadError, "Incomplete payload: expected #{length} bytes, got #{payload.bytesize}"
        end

        payload
      end

      sig { params(payload: String).returns(T::Hash[String, T.untyped]) }
      def parse_json(payload)
        JSON.parse(payload)
      rescue JSON::ParserError => e
        raise ParseError, "Invalid JSON: #{e.message}"
      end
    end
  end
end
