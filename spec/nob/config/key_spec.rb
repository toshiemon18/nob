require "spec_helper"

RSpec.describe Nob::Config::Key do
  describe "#to_s" do
    it "names a sectioned key as [section].name" do
      key = described_class.new(section: "dailyNote", name: "template", default: nil)

      expect(key.to_s).to(eq("[dailyNote].template"))
    end

    it "names a top-level key by its name alone" do
      key = described_class.new(section: nil, name: "vault", default: nil)

      expect(key.to_s).to(eq("vault"))
    end
  end

  describe "#read" do
    let(:key) { described_class.new(section: "dailyNote", name: "basePath", default: "daily/") }

    it "returns the value set in the section" do
      expect(key.read({"dailyNote" => {"basePath" => "journal/"}})).to(eq("journal/"))
    end

    it "falls back to the default when the key is absent" do
      expect(key.read({"dailyNote" => {}})).to(eq("daily/"))
    end

    it "falls back to the default when the section is absent" do
      expect(key.read({})).to(eq("daily/"))
    end

    it "keeps an empty string instead of falling back to the default" do
      expect(key.read({"dailyNote" => {"basePath" => ""}})).to(eq(""))
    end

    it "reads a top-level key" do
      vault = described_class.new(section: nil, name: "vault", default: nil)

      expect(vault.read({"vault" => "/v"})).to(eq("/v"))
    end
  end
end
