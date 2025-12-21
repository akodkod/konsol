# typed: false
# frozen_string_literal: true

RSpec.describe Konsol::Session::Evaluator do
  subject(:evaluator) { described_class.new }

  let(:binding_context) do
    context = Object.new
    context.instance_eval { binding }
  end

  describe "#evaluate" do
    it "evaluates simple expressions" do
      result = evaluator.evaluate("1 + 1", binding_context)

      expect(result.value).to eq("2")
      expect(result.value_type).to eq("Integer")
      expect(result.exception).to be_nil
    end

    it "preserves state across evaluations" do
      evaluator.evaluate("x = 123", binding_context)
      result = evaluator.evaluate("x + 1", binding_context)

      expect(result.value).to eq("124")
    end

    it "captures stdout" do
      result = evaluator.evaluate('puts "hello"', binding_context)

      expect(result.stdout).to eq("hello\n")
      expect(result.value).to eq("nil")
    end

    it "captures stderr" do
      result = evaluator.evaluate('$stderr.puts "error"', binding_context)

      expect(result.stderr).to eq("error\n")
    end

    it "captures exceptions" do
      result = evaluator.evaluate('raise "boom"', binding_context)

      expect(result.exception).not_to be_nil
      expect(result.exception.class_name).to eq("RuntimeError")
      expect(result.exception.message).to eq("boom")
      expect(result.exception.backtrace).not_to be_empty
    end

    it "handles syntax errors" do
      result = evaluator.evaluate("def foo(", binding_context)

      expect(result.exception).not_to be_nil
      expect(result.exception.class_name).to eq("SyntaxError")
    end

    it "restores stdout/stderr after evaluation" do
      original_stdout = $stdout
      original_stderr = $stderr

      evaluator.evaluate('puts "test"', binding_context)

      expect($stdout).to eq(original_stdout)
      expect($stderr).to eq(original_stderr)
    end

    it "converts result to protocol format" do
      result = evaluator.evaluate("42", binding_context)
      protocol_result = result.to_protocol

      expect(protocol_result).to be_a(Konsol::Protocol::Responses::EvalResult)
      expect(protocol_result.value).to eq("42")
    end
  end
end
