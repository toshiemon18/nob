require "spec_helper"

RSpec.describe Nob::Templates::Operators::Title do
  describe ".new" do
    it "constructs with fmt: nil" do
      expect(described_class.new(nil)).to(be_a(described_class))
    end

    it "raises UndefinedVariable when fmt is provided" do
      expect { described_class.new("foo") }.to(
        raise_error(
          Nob::Templates::UndefinedVariable,
          /title does not accept format: foo/
        )
      )
    end
  end

  describe "#call" do
    it "returns the title argument" do
      op = described_class.new(nil)
      expect(op.call(title: "Hello", now: Time.now)).to(eq("Hello"))
    end
  end

  describe "#==" do
    it "is equal when fmt matches" do
      expect(described_class.new(nil)).to(eq(described_class.new(nil)))
    end
  end
end
