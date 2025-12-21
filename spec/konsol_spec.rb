# typed: false
# frozen_string_literal: true

RSpec.describe Konsol do
  it "has a version number" do
    expect(Konsol::VERSION).not_to be_nil
  end

  it "defines an Error class" do
    expect(Konsol::Error).to be < StandardError
  end
end
