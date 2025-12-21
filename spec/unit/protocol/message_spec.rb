# typed: false
# frozen_string_literal: true

RSpec.describe Konsol::Protocol do
  describe Konsol::Protocol::Request do
    describe ".from_hash" do
      it "parses a valid request" do
        raw = {
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => { "clientInfo" => { "name" => "test" } },
        }

        request = described_class.from_hash(raw)

        expect(request.jsonrpc).to eq("2.0")
        expect(request.id).to eq(1)
        expect(request.method_name).to eq("initialize")
        expect(request.params).to eq({ "clientInfo" => { "name" => "test" } })
      end

      it "handles missing params" do
        raw = { "jsonrpc" => "2.0", "id" => 1, "method" => "shutdown" }

        request = described_class.from_hash(raw)

        expect(request.params).to be_nil
      end

      it "handles string id" do
        raw = { "jsonrpc" => "2.0", "id" => "abc-123", "method" => "test" }

        request = described_class.from_hash(raw)

        expect(request.id).to eq("abc-123")
      end

      it "handles null id" do
        raw = { "jsonrpc" => "2.0", "id" => nil, "method" => "test" }

        request = described_class.from_hash(raw)

        expect(request.id).to be_nil
      end
    end
  end

  describe Konsol::Protocol::Response do
    describe ".success" do
      it "creates a success response" do
        response = described_class.success(1, { "key" => "value" })

        expect(response.id).to eq(1)
        expect(response.result).to eq({ "key" => "value" })
        expect(response.error).to be_nil
      end
    end

    describe ".error" do
      it "creates an error response" do
        error = Konsol::Protocol::ErrorData.new(code: -32_600, message: "Invalid Request")
        response = described_class.error(1, error)

        expect(response.id).to eq(1)
        expect(response.result).to be_nil
        expect(response.error.code).to eq(-32_600)
      end
    end

    describe "#to_h" do
      it "serializes success response" do
        response = described_class.success(1, nil)

        expect(response.to_h).to eq({
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => nil,
        })
      end

      it "serializes error response" do
        error = Konsol::Protocol::ErrorData.new(code: -32_600, message: "Invalid Request")
        response = described_class.error(1, error)

        expect(response.to_h).to eq({
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => { "code" => -32_600, "message" => "Invalid Request" },
        })
      end
    end
  end

  describe Konsol::Protocol::ErrorCode do
    it "has correct error codes" do
      expect(Konsol::Protocol::ErrorCode::ParseError.code).to eq(-32_700)
      expect(Konsol::Protocol::ErrorCode::InvalidRequest.code).to eq(-32_600)
      expect(Konsol::Protocol::ErrorCode::MethodNotFound.code).to eq(-32_601)
      expect(Konsol::Protocol::ErrorCode::SessionNotFound.code).to eq(-32_001)
    end

    it "provides error messages" do
      expect(Konsol::Protocol::ErrorCode::ParseError.message).to eq("Invalid JSON")
      expect(Konsol::Protocol::ErrorCode::SessionNotFound.message).to eq("Session ID does not exist")
    end
  end

  describe Konsol::Protocol::Method do
    describe ".from_name" do
      it "finds method by name" do
        expect(described_class.from_name("initialize")).to eq(Konsol::Protocol::Method::Initialize)
        expect(described_class.from_name("konsol/eval")).to eq(Konsol::Protocol::Method::Eval)
      end

      it "returns nil for unknown methods" do
        expect(described_class.from_name("unknown")).to be_nil
      end
    end

    describe "#notification?" do
      it "identifies notifications" do
        expect(Konsol::Protocol::Method::Exit.notification?).to be true
        expect(Konsol::Protocol::Method::Initialize.notification?).to be false
      end
    end
  end
end
