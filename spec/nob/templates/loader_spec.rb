require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Templates::Loader do
  describe ".read" do
    it "returns nil when path is nil" do
      expect(described_class.read(nil)).to be_nil
    end

    it "raises Nob::Error mentioning the path when the file does not exist" do
      Dir.mktmpdir("nob-loader") do |dir|
        missing = File.join(dir, "not-here.md")

        expect {
          described_class.read(missing)
        }.to raise_error(Nob::Error, /template file not found.*#{Regexp.escape(missing)}/)
      end
    end

    it "returns the file contents when the path exists" do
      Dir.mktmpdir("nob-loader") do |dir|
        path = File.join(dir, "tpl.md")
        File.write(path, "# {{title}}\n")

        expect(described_class.read(path)).to eq("# {{title}}\n")
      end
    end
  end
end
