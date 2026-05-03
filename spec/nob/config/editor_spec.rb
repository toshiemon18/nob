require "spec_helper"

RSpec.describe Nob::Config::Editor do
  describe ".resolve" do
    it "returns 'vi' when env has no EDITOR" do
      expect(described_class.resolve(env: {})).to eq("vi")
    end

    it "returns ENV['EDITOR'] when set" do
      expect(described_class.resolve(env: {"EDITOR" => "nvim"})).to eq("nvim")
    end

    it "returns 'vi' when EDITOR is empty string" do
      expect(described_class.resolve(env: {"EDITOR" => ""})).to eq("vi")
    end

    it "returns 'vi' when EDITOR is whitespace only" do
      expect(described_class.resolve(env: {"EDITOR" => "   "})).to eq("vi")
    end

    it "strips surrounding whitespace from EDITOR" do
      expect(described_class.resolve(env: {"EDITOR" => "  code -w  "})).to eq("code -w")
    end
  end
end
