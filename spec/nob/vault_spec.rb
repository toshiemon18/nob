require "spec_helper"
require "tmpdir"
require "fileutils"
require "date"

RSpec.describe Nob::Vault do
  let(:vault) { Dir.mktmpdir("nob-vault") }

  after { FileUtils.remove_entry(vault) }

  def touch(relative_path, content = "")
    abs = File.join(vault, relative_path)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, content)
    abs
  end

  describe ".path_for" do
    it "joins vault and segments" do
      expect(described_class.path_for("/v", "projects", "Plan.md")).to(eq("/v/projects/Plan.md"))
    end

    it "skips nil segments" do
      expect(described_class.path_for("/v", nil, "Plan.md")).to(eq("/v/Plan.md"))
    end

    it "skips empty-string segments" do
      expect(described_class.path_for("/v", "", "Plan.md")).to(eq("/v/Plan.md"))
    end

    it "returns vault when only nil/empty segments are given" do
      expect(described_class.path_for("/v", nil, "")).to(eq("/v"))
    end
  end

  describe ".exists? and .size" do
    it "reports existence and size of a file" do
      abs = touch("a.md", "x" * 10)

      expect(described_class.exists?(abs)).to(be(true))
      expect(described_class.size(abs)).to(eq(10))
    end

    it "returns false for missing files" do
      expect(described_class.exists?(File.join(vault, "missing.md"))).to(be(false))
    end
  end

  describe ".write" do
    it "writes content to the path" do
      target = File.join(vault, "a.md")

      described_class.write(target, "hello")

      expect(File.read(target)).to(eq("hello"))
    end

    it "creates intermediate directories" do
      target = File.join(vault, "deep/nested/dir/a.md")

      described_class.write(target, "hi")

      expect(File.read(target)).to(eq("hi"))
    end

    it "overwrites an existing file without error" do
      target = touch("a.md", "old")

      described_class.write(target, "new")

      expect(File.read(target)).to(eq("new"))
    end
  end

  describe ".list" do
    it "returns a single relative path for one .md file at the vault root" do
      touch("README.md")

      expect(described_class.list(vault)).to(eq(["README.md"]))
    end

    it "recursively collects .md files from nested directories" do
      touch("a.md")
      touch("projects/b.md")
      touch("daily/2026/04/c.md")

      expect(described_class.list(vault)).to(contain_exactly("a.md", "projects/b.md", "daily/2026/04/c.md"))
    end

    it "ignores non-markdown files" do
      touch("note.md")
      touch("readme.txt")
      touch("image.png")

      expect(described_class.list(vault)).to(eq(["note.md"]))
    end

    it "skips dotfiles and dot-directories" do
      touch("visible.md")
      touch(".hidden.md")
      touch(".obsidian/config.md")
      touch("nested/.cache/x.md")

      expect(described_class.list(vault)).to(eq(["visible.md"]))
    end

    it "returns entries sorted by relative_path ascending" do
      touch("zeta.md")
      touch("alpha.md")
      touch("mid/beta.md")

      expect(described_class.list(vault)).to(eq(["alpha.md", "mid/beta.md", "zeta.md"]))
    end

    it "filters by prefix to a single subdirectory" do
      touch("daily/2026-04-27.md")
      touch("daily/2026-04-28.md")
      touch("projects/Plan.md")
      touch("README.md")

      expect(described_class.list(vault, prefix: "daily")).to(eq(["daily/2026-04-27.md", "daily/2026-04-28.md"]))
    end

    it "recursively collects under a nested prefix" do
      touch("daily/2026/04/x.md")
      touch("daily/2026/05/y.md")
      touch("projects/z.md")

      expect(described_class.list(vault, prefix: "daily/2026")).to(eq(["daily/2026/04/x.md", "daily/2026/05/y.md"]))
    end

    it "treats prefix with trailing slash as equivalent" do
      touch("daily/a.md")

      with_slash = described_class.list(vault, prefix: "daily/")
      without_slash = described_class.list(vault, prefix: "daily")

      expect(with_slash).to(eq(without_slash))
      expect(with_slash).to(eq(["daily/a.md"]))
    end

    it "raises PrefixNotFound when the prefix directory does not exist" do
      touch("daily/a.md")

      expect {
        described_class.list(vault, prefix: "missing")
      }
        .to(raise_error(Nob::Vault::PrefixNotFound, /missing/))
    end

    it "raises InvalidPrefix when the prefix is an absolute path" do
      expect {
        described_class.list(vault, prefix: "/etc")
      }
        .to(raise_error(Nob::Vault::InvalidPrefix))
    end

    it "raises InvalidPrefix when the prefix escapes the vault via .." do
      expect {
        described_class.list(vault, prefix: "../outside")
      }
        .to(raise_error(Nob::Vault::InvalidPrefix))
    end

    it "raises InvalidPrefix when the prefix points to a file" do
      touch("notes.md")

      expect {
        described_class.list(vault, prefix: "notes.md")
      }
        .to(raise_error(Nob::Vault::InvalidPrefix))
    end
  end

  describe ".backup" do
    it "renames the file with a timestamp suffix and returns the new path" do
      abs = touch("a.md", "original")
      now = Time.new(2026, 4, 27, 10, 30, 45)

      result = described_class.backup(abs, now: now)

      expect(result).to(eq(File.join(vault, "a.backup-20260427-103045.md")))
      expect(File.exist?(abs)).to(be(false))
      expect(File.read(result)).to(eq("original"))
    end

    it "raises Nob::Error when the backup target already exists" do
      abs = touch("a.md", "x")
      now = Time.new(2026, 4, 27, 10, 30, 45)
      File.write(File.join(vault, "a.backup-20260427-103045.md"), "blocker")

      expect {
        described_class.backup(abs, now: now)
      }
        .to(raise_error(Nob::Error, /backup target already exists/))
    end
  end

  describe ".frontmatter" do
    it "returns empty frontmatter and full body when the file has no frontmatter" do
      abs = touch("a.md", "hello world")

      result = described_class.frontmatter(abs)

      expect(result[:frontmatter]).to(eq({}))
      expect(result[:body]).to(eq("hello world"))
    end

    it "parses YAML frontmatter and excludes it from the body" do
      file = <<~MD
        ---
        title: My Note
        date: 2026-04-27
        ---

        body here
      MD
      abs = touch("note.md", file)

      result = described_class.frontmatter(abs)

      expect(result[:frontmatter]).to(eq("title" => "My Note", "date" => Date.new(2026, 4, 27)))
      expect(result[:body]).to(eq("body here\n"))
    end

    it "preserves the YAML key order" do
      file = <<~MD
        ---
        zeta: 1
        alpha: 2
        mid: 3
        ---

        body
      MD
      abs = touch("ordered.md", file)

      expect(described_class.frontmatter(abs)[:frontmatter].keys).to(eq(%w[zeta alpha mid]))
    end

    it "raises InvalidFrontmatter when the YAML cannot be parsed" do
      file = <<~MD
        ---
        title: : : invalid
        - broken
        ---

        body
      MD
      abs = touch("broken.md", file)

      expect {
        described_class.frontmatter(abs)
      }
        .to(raise_error(Nob::Vault::InvalidFrontmatter))
    end
  end
end
