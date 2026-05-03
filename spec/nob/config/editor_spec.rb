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

  describe ".open" do
    let(:path) { "/tmp/nob-config-test.toml" }

    let(:fake_runner) do
      Class.new do
        attr_reader :calls

        def initialize(result)
          @result = result
          @calls = []
        end

        def system(*args)
          @calls << args
          @result
        end
      end
    end

    it "passes a command containing editor name and escaped path to runner" do
      runner = fake_runner.new(true)
      described_class.open(path: path, env: {"EDITOR" => "nvim"}, runner: runner)
      expect(runner.calls.length).to eq(1)
      cmd = runner.calls.first.first
      expect(cmd).to include("nvim")
      expect(cmd).to include("nob-config-test.toml")
    end

    it "uses 'vi' fallback when EDITOR is unset" do
      runner = fake_runner.new(true)
      described_class.open(path: path, env: {}, runner: runner)
      expect(runner.calls.first.first).to start_with("vi ")
    end

    it "raises Nob::Error when runner returns nil (failed to launch)" do
      runner = fake_runner.new(nil)
      expect {
        described_class.open(path: path, env: {"EDITOR" => "missing-editor"}, runner: runner)
      }.to raise_error(Nob::Error, /failed to launch editor/)
    end

    it "raises Nob::Error when runner returns false (non-zero exit)" do
      runner = fake_runner.new(false)
      expect {
        described_class.open(path: path, env: {"EDITOR" => "vi"}, runner: runner)
      }.to raise_error(Nob::Error, /editor exited with non-zero status/)
    end
  end
end
