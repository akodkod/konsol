# typed: false
# frozen_string_literal: true

RSpec.describe Konsol::Util::CaseTransform do
  describe ".to_camel_case" do
    it "converts simple snake_case keys to camelCase" do
      input = { "foo_bar" => "value" }
      expect(described_class.to_camel_case(input)).to eq({ "fooBar" => "value" })
    end

    it "handles nested hashes" do
      input = { "outer_key" => { "inner_key" => "value" } }
      expected = { "outerKey" => { "innerKey" => "value" } }
      expect(described_class.to_camel_case(input)).to eq(expected)
    end

    it "handles arrays of hashes" do
      input = { "items" => [{ "item_name" => "a" }, { "item_name" => "b" }] }
      expected = { "items" => [{ "itemName" => "a" }, { "itemName" => "b" }] }
      expect(described_class.to_camel_case(input)).to eq(expected)
    end

    it "preserves non-hash values" do
      expect(described_class.to_camel_case("string")).to eq("string")
      expect(described_class.to_camel_case(123)).to eq(123)
      expect(described_class.to_camel_case(nil)).to be_nil
    end

    it "handles symbol keys" do
      input = { foo_bar: "value" }
      expect(described_class.to_camel_case(input)).to eq({ "fooBar" => "value" })
    end
  end

  describe ".to_snake_case" do
    it "converts simple camelCase keys to snake_case" do
      input = { "fooBar" => "value" }
      expect(described_class.to_snake_case(input)).to eq({ "foo_bar" => "value" })
    end

    it "handles nested hashes" do
      input = { "outerKey" => { "innerKey" => "value" } }
      expected = { "outer_key" => { "inner_key" => "value" } }
      expect(described_class.to_snake_case(input)).to eq(expected)
    end

    it "handles arrays of hashes" do
      input = { "items" => [{ "itemName" => "a" }, { "itemName" => "b" }] }
      expected = { "items" => [{ "item_name" => "a" }, { "item_name" => "b" }] }
      expect(described_class.to_snake_case(input)).to eq(expected)
    end

    it "preserves non-hash values" do
      expect(described_class.to_snake_case("string")).to eq("string")
      expect(described_class.to_snake_case(123)).to eq(123)
      expect(described_class.to_snake_case(nil)).to be_nil
    end
  end

  describe ".snake_to_camel" do
    it "converts snake_case to camelCase" do
      expect(described_class.snake_to_camel("foo_bar")).to eq("fooBar")
      expect(described_class.snake_to_camel("foo_bar_baz")).to eq("fooBarBaz")
    end

    it "preserves strings without underscores" do
      expect(described_class.snake_to_camel("foobar")).to eq("foobar")
    end
  end

  describe ".camel_to_snake" do
    it "converts camelCase to snake_case" do
      expect(described_class.camel_to_snake("fooBar")).to eq("foo_bar")
      expect(described_class.camel_to_snake("fooBarBaz")).to eq("foo_bar_baz")
    end

    it "preserves strings without uppercase" do
      expect(described_class.camel_to_snake("foobar")).to eq("foobar")
    end

    it "handles leading uppercase" do
      expect(described_class.camel_to_snake("FooBar")).to eq("foo_bar")
    end
  end
end
