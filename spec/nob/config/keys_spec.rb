require "spec_helper"

RSpec.describe Nob::Config::Keys do
  describe ".all" do
    it "collects every key defined in Keys" do
      expect(described_class.all.map(&:to_s)).to(
        contain_exactly(
          "vault",
          "[dailyNote].basePath",
          "[dailyNote].fileNameFormat",
          "[dailyNote].template",
          "[note].template"
        )
      )
    end
  end
end
