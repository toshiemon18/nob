require "spec_helper"

RSpec.describe Nob::Templates::Operators::Time do
  let(:now) { ::Time.new(2026, 5, 3, 9, 7, 30) }

  describe "#call" do
    it "returns HH:MM when fmt is nil" do
      expect(described_class.new(nil).call(title: "x", now: now)).to(eq("09:07"))
    end

    it "returns unix timestamp when fmt is 'timestamp'" do
      expect(described_class.new("timestamp").call(title: "x", now: now)).to(eq(now.to_i.to_s))
    end

    it "delegates to strftime for other formats" do
      expect(described_class.new("%H:%M:%S").call(title: "x", now: now)).to(eq("09:07:30"))
    end
  end
end
