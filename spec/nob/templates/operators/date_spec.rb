require "spec_helper"

RSpec.describe Nob::Templates::Operators::Date do
  let(:now) { Time.new(2026, 5, 3, 9, 0, 0) }

  describe "#call" do
    it "returns YYYY-MM-DD when fmt is nil" do
      expect(described_class.new(nil).call(title: "x", now: now)).to(eq("2026-05-03"))
    end

    it "returns unix timestamp when fmt is 'timestamp'" do
      expect(described_class.new("timestamp").call(title: "x", now: now)).to(eq(now.to_i.to_s))
    end

    it "delegates to strftime for other formats" do
      expect(described_class.new("%Y/%m/%d").call(title: "x", now: now)).to(eq("2026/05/03"))
    end
  end
end
