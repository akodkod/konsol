# typed: false
# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

module Konsol
  module Test
    class JsonRpcClient
      attr_reader :stdin, :stdout, :stderr, :wait_thr

      def initialize(app_path:, timeout: 10)
        @app_path = app_path
        @timeout = timeout
        @request_id = 0
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thr = nil
      end

      def start
        env = { "RAILS_ENV" => "test", "BUNDLE_GEMFILE" => File.join(@app_path, "Gemfile") }
        cmd = ["bundle", "exec", "konsol", "--stdio"]

        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(env, *cmd, chdir: @app_path)
        @stdout.binmode
        @stdin.binmode

        self
      end

      # rubocop:disable Metrics/MethodLength
      def stop
        return unless @stdin

        # Try graceful shutdown
        begin
          send_notification("exit")
        rescue StandardError
          nil
        end

        begin
          @stdin.close
        rescue StandardError
          nil
        end
        begin
          @stdout.close
        rescue StandardError
          nil
        end
        begin
          @stderr.close
        rescue StandardError
          nil
        end

        # Wait for process to exit
        begin
          Timeout.timeout(2) { @wait_thr.value }
        rescue Timeout::Error
          begin
            Process.kill("KILL", @wait_thr.pid)
          rescue StandardError
            nil
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      def send_request(method, params = nil)
        @request_id += 1
        message = {
          "jsonrpc" => "2.0",
          "id" => @request_id,
          "method" => method,
        }
        message["params"] = params if params

        write_message(message)
        read_response
      end

      def send_notification(method, params = nil)
        message = {
          "jsonrpc" => "2.0",
          "method" => method,
        }
        message["params"] = params if params

        write_message(message)
        nil
      end

      private

      def write_message(message)
        json = JSON.generate(message)
        frame = "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
        @stdin.write(frame)
        @stdin.flush
      end

      def read_response
        Timeout.timeout(@timeout) do
          # Read headers
          content_length = nil
          loop do
            line = @stdout.gets("\r\n")
            raise "Unexpected EOF reading headers" if line.nil?

            break if line == "\r\n"

            if (match = line.match(/^Content-Length:\s*(\d+)/i))
              content_length = match[1].to_i
            end
          end

          raise "Missing Content-Length header" unless content_length

          # Read payload
          payload = @stdout.read(content_length)
          raise "Incomplete payload" if payload.nil? || payload.bytesize < content_length

          JSON.parse(payload)
        end
      end
    end
  end
end
