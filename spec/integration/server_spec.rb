# typed: false
# frozen_string_literal: true

require "stringio"

RSpec.describe Konsol::Server do
  let(:input) { StringIO.new }
  let(:output) { StringIO.new }
  let(:server) { described_class.new(input: input, output: output) }

  def write_request(id:, method:, params: nil)
    message = { "jsonrpc" => "2.0", "id" => id, "method" => method }
    message["params"] = params if params
    json = JSON.generate(message)
    input.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
    input.rewind
  end

  def write_notification(method:, params: nil)
    message = { "jsonrpc" => "2.0", "method" => method }
    message["params"] = params if params
    json = JSON.generate(message)
    input.write("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
    input.rewind
  end

  def read_response
    output.rewind
    content = output.read
    return nil if content.empty?

    # Parse the framed response
    match = content.match(/Content-Length: (\d+)\r\n\r\n(.+)/m)
    return nil unless match

    JSON.parse(match[2])
  end

  describe "#run with initialize request" do
    it "returns server info and capabilities" do
      write_request(id: 1, method: "initialize", params: { "clientInfo" => { "name" => "test" } })

      # The server will block waiting for more input after processing
      # So we need to add an exit notification
      input.write("")
      begin
        input.close_write
      rescue StandardError
        nil
      end

      # Run in a thread with timeout since server loops
      thread = Thread.new { server.run }
      sleep 0.1
      thread.kill

      response = read_response
      expect(response).not_to be_nil
      expect(response["id"]).to eq(1)
      expect(response["result"]["serverInfo"]["name"]).to eq("konsol")
      expect(response["result"]["serverInfo"]["version"]).to eq(Konsol::VERSION)
      expect(response["result"]["capabilities"]).to include("supportsInterrupt" => false)
    end
  end

  describe "#run with shutdown request" do
    it "returns null result" do
      # First initialize, then shutdown
      msg1 = { "jsonrpc" => "2.0", "id" => 1, "method" => "initialize" }
      msg2 = { "jsonrpc" => "2.0", "id" => 2, "method" => "shutdown" }

      json1 = JSON.generate(msg1)
      json2 = JSON.generate(msg2)

      input.write("Content-Length: #{json1.bytesize}\r\n\r\n#{json1}")
      input.write("Content-Length: #{json2.bytesize}\r\n\r\n#{json2}")
      input.rewind

      thread = Thread.new { server.run }
      sleep 0.1
      thread.kill

      output.rewind
      content = output.read

      # Should have two responses
      responses = content.scan(/Content-Length: (\d+)\r\n\r\n(.+?)(?=Content-Length:|$)/m)
      expect(responses.length).to be >= 2

      shutdown_response = JSON.parse(responses[1][1])
      expect(shutdown_response["id"]).to eq(2)
      expect(shutdown_response["result"]).to be_nil
    end
  end

  describe "#run with unknown method" do
    it "returns MethodNotFound error" do
      write_request(id: 1, method: "unknown/method")

      thread = Thread.new { server.run }
      sleep 0.1
      thread.kill

      response = read_response
      expect(response).not_to be_nil
      expect(response["id"]).to eq(1)
      expect(response["error"]).not_to be_nil
      expect(response["error"]["code"]).to eq(-32_601)
    end
  end

  describe "#run with exit notification" do
    it "terminates the server" do
      write_notification(method: "exit")

      exit_code = server.run
      # Exit without shutdown returns 1
      expect(exit_code).to eq(1)
    end

    it "returns 0 after proper shutdown" do
      msg1 = { "jsonrpc" => "2.0", "id" => 1, "method" => "shutdown" }
      msg2 = { "jsonrpc" => "2.0", "method" => "exit" }

      json1 = JSON.generate(msg1)
      json2 = JSON.generate(msg2)

      input.write("Content-Length: #{json1.bytesize}\r\n\r\n#{json1}")
      input.write("Content-Length: #{json2.bytesize}\r\n\r\n#{json2}")
      input.rewind

      exit_code = server.run
      expect(exit_code).to eq(0)
    end
  end
end
