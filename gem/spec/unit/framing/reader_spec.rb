# typed: false
# frozen_string_literal: true

require "stringio"

RSpec.describe Konsol::Framing::Reader do
  def create_frame(payload)
    json = payload.is_a?(String) ? payload : JSON.generate(payload)
    "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
  end

  describe "#read" do
    it "reads and parses a valid JSON-RPC message" do
      message = { "jsonrpc" => "2.0", "id" => 1, "method" => "test" }
      io = StringIO.new(create_frame(message))
      reader = described_class.new(io)

      result = reader.read
      expect(result).to eq(message)
    end

    it "handles multiple messages" do
      msg1 = { "jsonrpc" => "2.0", "id" => 1, "method" => "first" }
      msg2 = { "jsonrpc" => "2.0", "id" => 2, "method" => "second" }
      io = StringIO.new(create_frame(msg1) + create_frame(msg2))
      reader = described_class.new(io)

      expect(reader.read).to eq(msg1)
      expect(reader.read).to eq(msg2)
    end

    it "returns nil on EOF" do
      io = StringIO.new("")
      reader = described_class.new(io)

      expect(reader.read).to be_nil
    end

    it "handles case-insensitive Content-Length header" do
      message = { "jsonrpc" => "2.0", "id" => 1 }
      json = JSON.generate(message)
      io = StringIO.new("content-length: #{json.bytesize}\r\n\r\n#{json}")
      reader = described_class.new(io)

      expect(reader.read).to eq(message)
    end

    it "ignores extra headers" do
      message = { "jsonrpc" => "2.0", "id" => 1 }
      json = JSON.generate(message)
      io = StringIO.new("Content-Type: application/json\r\nContent-Length: #{json.bytesize}\r\n\r\n#{json}")
      reader = described_class.new(io)

      expect(reader.read).to eq(message)
    end

    it "handles UTF-8 content correctly (byte length vs char length)" do
      message = { "emoji" => "\u{1F600}" } # Grinning face emoji (4 bytes)
      json = JSON.generate(message)
      io = StringIO.new("Content-Length: #{json.bytesize}\r\n\r\n#{json}")
      reader = described_class.new(io)

      expect(reader.read).to eq(message)
    end

    it "raises ParseError for invalid JSON" do
      io = StringIO.new("Content-Length: 5\r\n\r\n{bad}")
      reader = described_class.new(io)

      expect { reader.read }.to raise_error(Konsol::Framing::Reader::ParseError, /Invalid JSON/)
    end

    it "raises ReadError for missing Content-Length header" do
      io = StringIO.new("Content-Type: application/json\r\n\r\n{}")
      reader = described_class.new(io)

      expect { reader.read }.to raise_error(Konsol::Framing::Reader::ReadError, /Missing Content-Length/)
    end

    it "raises ReadError for incomplete payload" do
      io = StringIO.new("Content-Length: 100\r\n\r\n{}")
      reader = described_class.new(io)

      expect { reader.read }.to raise_error(Konsol::Framing::Reader::ReadError, /Incomplete payload/)
    end
  end
end
