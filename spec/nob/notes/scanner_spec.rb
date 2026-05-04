require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Nob::Notes::Scanner do
  let(:base) { Dir.mktmpdir("nob-scanner-base") }

  after { FileUtils.remove_entry(base) }

  def touch(relative_path, content = "")
    abs = File.join(base, relative_path)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, content)
    abs
  end

  describe ".markdown_files" do
    it "lists only .md files relative to the base" do
      touch("a.md")
      touch("nested/b.md")
      touch("readme.txt")
      touch("image.png")

      expect(described_class.markdown_files(base)).to eq(["a.md", "nested/b.md"])
    end

    it "returns the relative paths sorted ascending" do
      touch("zeta.md")
      touch("alpha.md")
      touch("mid/beta.md")

      expect(described_class.markdown_files(base)).to eq(["alpha.md", "mid/beta.md", "zeta.md"])
    end

    it "skips dotfiles and dot-directories" do
      touch("visible.md")
      touch(".hidden.md")
      touch(".obsidian/config.md")
      touch("nested/.cache/x.md")

      expect(described_class.markdown_files(base)).to eq(["visible.md"])
    end

    it "returns an empty array when the base has no markdown files" do
      touch("note.txt")

      expect(described_class.markdown_files(base)).to eq([])
    end
  end
end
