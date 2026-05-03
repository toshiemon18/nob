require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Nob::Notes::Lister do
  let(:vault) { Dir.mktmpdir("nob-vault") }

  after { FileUtils.remove_entry(vault) }

  def touch(relative_path, content = "")
    abs = File.join(vault, relative_path)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, content)
    abs
  end

  describe ".list" do
    it "returns Nob::Entities::Note instances" do
      touch("README.md", "# hi")

      result = described_class.list(vault: vault)

      expect(result.first).to be_a(Nob::Entities::Note)
    end

    it "returns a single entry for one .md file at the vault root" do
      abs = touch("README.md", "# hi")

      result = described_class.list(vault: vault)

      expect(result.size).to eq(1)
      expect(result.first.relative_path).to eq("README.md")
      expect(result.first.absolute_path).to eq(abs)
    end

    it "recursively collects .md files from nested directories" do
      touch("a.md")
      touch("projects/b.md")
      touch("daily/2026/04/c.md")

      result = described_class.list(vault: vault).map(&:relative_path)

      expect(result).to contain_exactly("a.md", "projects/b.md", "daily/2026/04/c.md")
    end

    it "ignores non-markdown files" do
      touch("note.md")
      touch("readme.txt")
      touch("image.png")

      result = described_class.list(vault: vault).map(&:relative_path)

      expect(result).to eq(["note.md"])
    end

    it "skips dotfiles and dot-directories" do
      touch("visible.md")
      touch(".hidden.md")
      touch(".obsidian/config.md")
      touch("nested/.cache/x.md")

      result = described_class.list(vault: vault).map(&:relative_path)

      expect(result).to eq(["visible.md"])
    end

    it "returns entries sorted by relative_path ascending" do
      touch("zeta.md")
      touch("alpha.md")
      touch("mid/beta.md")

      result = described_class.list(vault: vault).map(&:relative_path)

      expect(result).to eq(["alpha.md", "mid/beta.md", "zeta.md"])
    end

    it "filters by prefix to a single subdirectory" do
      touch("daily/2026-04-27.md")
      touch("daily/2026-04-28.md")
      touch("projects/Plan.md")
      touch("README.md")

      result = described_class.list(vault: vault, prefix: "daily").map(&:relative_path)

      expect(result).to eq(["daily/2026-04-27.md", "daily/2026-04-28.md"])
    end

    it "recursively collects under a nested prefix" do
      touch("daily/2026/04/x.md")
      touch("daily/2026/05/y.md")
      touch("projects/z.md")

      result = described_class.list(vault: vault, prefix: "daily/2026").map(&:relative_path)

      expect(result).to eq(["daily/2026/04/x.md", "daily/2026/05/y.md"])
    end

    it "treats prefix with trailing slash as equivalent" do
      touch("daily/a.md")

      with_slash = described_class.list(vault: vault, prefix: "daily/").map(&:relative_path)
      without_slash = described_class.list(vault: vault, prefix: "daily").map(&:relative_path)

      expect(with_slash).to eq(without_slash)
      expect(with_slash).to eq(["daily/a.md"])
    end

    it "raises PrefixNotFound when the prefix directory does not exist" do
      touch("daily/a.md")

      expect {
        described_class.list(vault: vault, prefix: "missing")
      }.to raise_error(Nob::Notes::Lister::PrefixNotFound, /missing/)
    end

    it "raises InvalidPrefix when the prefix is an absolute path" do
      expect {
        described_class.list(vault: vault, prefix: "/etc")
      }.to raise_error(Nob::Notes::Lister::InvalidPrefix)
    end

    it "raises InvalidPrefix when the prefix escapes the vault via .." do
      expect {
        described_class.list(vault: vault, prefix: "../outside")
      }.to raise_error(Nob::Notes::Lister::InvalidPrefix)
    end

    it "raises InvalidPrefix when the prefix points to a file" do
      touch("notes.md")

      expect {
        described_class.list(vault: vault, prefix: "notes.md")
      }.to raise_error(Nob::Notes::Lister::InvalidPrefix)
    end
  end
end
