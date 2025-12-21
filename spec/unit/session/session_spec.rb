# typed: false
# frozen_string_literal: true

RSpec.describe Konsol::Session::Session do
  subject(:session) { described_class.new }

  describe "#initialize" do
    it "generates a UUID id" do
      expect(session.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it "creates a binding" do
      expect(session.session_binding).to be_a(Binding)
    end

    it "starts in idle state" do
      expect(session.state).to eq(Konsol::Session::State::Idle)
      expect(session.idle?).to be true
      expect(session.busy?).to be false
    end
  end

  describe "#mark_busy!" do
    it "changes state to busy" do
      session.mark_busy!

      expect(session.busy?).to be true
      expect(session.idle?).to be false
    end
  end

  describe "#mark_idle!" do
    it "changes state to idle" do
      session.mark_busy!
      session.mark_idle!

      expect(session.idle?).to be true
      expect(session.busy?).to be false
    end
  end

  describe "#mark_interrupted!" do
    it "changes state to interrupted" do
      session.mark_busy!
      session.mark_interrupted!

      expect(session.state).to eq(Konsol::Session::State::Interrupted)
    end
  end

  describe "session binding" do
    it "can evaluate code" do
      result = eval("1 + 1", session.session_binding, __FILE__, __LINE__)
      expect(result).to eq(2)
    end

    it "preserves local variables" do
      eval("x = 42", session.session_binding, __FILE__, __LINE__)
      result = eval("x", session.session_binding, __FILE__, __LINE__)
      expect(result).to eq(42)
    end
  end
end
