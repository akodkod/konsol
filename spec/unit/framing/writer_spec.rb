# typed: false
# frozen_string_literal: true

require "stringio"

RSpec.describe Konsol::Framing::Writer do
  describe "#write" do
    it "writes a JSON-RPC message with Content-Length header" do
      io = StringIO.new
      writer = described_class.new(io)
      message = { "jsonrpc" => "2.0", "id" => 1, "result" => nil }

      writer.write(message)

      io.rewind
      output = io.read
      json = JSON.generate(message)

      expect(output).to eq("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
    end

    it "correctly calculates byte length for UTF-8 content" do
      io = StringIO.new
      writer = described_class.new(io)
      message = { "emoji" => "\u{1F600}" } # 4 bytes

      writer.write(message)

      io.rewind
      output = io.read
      json = JSON.generate(message)

      expect(output).to include("Content-Length: #{json.bytesize}")
    end

    it "writes multiple messages" do
      io = StringIO.new
      writer = described_class.new(io)

      writer.write({ "id" => 1 })
      writer.write({ "id" => 2 })

      io.rewind
      output = io.read

      expect(output).to include("Content-Length: 8")
      expect(output).to include('{"id":1}')
      expect(output).to include('{"id":2}')
    end
  end
end
