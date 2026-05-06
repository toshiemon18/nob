require "spec_helper"

RSpec.describe Nob::Templates::Operators::Id do
  let(:now) { Time.new(2026, 5, 3, 9, 7, 30) }

  describe ".new" do
    it "raises UndefinedVariable when fmt is provided" do
      expect { described_class.new("foo") }.to(
        raise_error(
          Nob::Templates::UndefinedVariable,
          /id does not accept format: foo/
        )
      )
    end
  end

  describe "#call" do
    it "returns YYYYMMDDHHMMSS" do
      expect(described_class.new(nil).call(title: "x", now: now)).to(eq("20260503090730"))
    end
  end
end
