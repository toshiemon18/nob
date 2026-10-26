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

    it "allows .. that stays inside the vault" do
      expect(described_class.path_for("/v", "a/../b.md")).to(eq("/v/a/../b.md"))
    end

    it "allows any segment when the vault is the filesystem root" do
      expect(described_class.path_for("/", "a.md")).to(eq("/a.md"))
    end

    it "raises InvalidPath when a segment escapes the vault via .." do
      expect { described_class.path_for("/v", "../x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, "path escapes the vault: ../x.md")
      )
    end

    it "raises InvalidPath when nested .. climbs above the vault" do
      expect { described_class.path_for("/v", "a/../../x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, /escapes the vault/)
      )
    end

    it "raises InvalidPath for a sibling directory sharing the vault name prefix" do
      expect { described_class.path_for("/vault", "../vault2/x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, /escapes the vault/)
      )
    end

    it "raises InvalidPath when the escape spans multiple segments" do
      expect { described_class.path_for("/v", "..", "x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, "path escapes the vault: ../x.md")
      )
    end

    it "raises InvalidPath when a segment is an absolute path" do
      expect { described_class.path_for("/v", "/etc", "x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, "path must be relative to the vault: /etc")
      )
    end

    it "defines InvalidPath as a Nob::Error" do
      expect(Nob::Vault::InvalidPath.ancestors).to(include(Nob::Error))
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
    it "skips directories whose names end in .md" do
      touch("a.md")
      touch("archive.md/b.md")

      expect(described_class.list(vault)).to(eq(["a.md", "archive.md/b.md"]))
    end

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
        .to(raise_error(Nob::Vault::InvalidPrefix, "prefix must be relative to the vault: /etc"))
    end

    it "raises InvalidPrefix when the prefix escapes the vault via .." do
      expect {
        described_class.list(vault, prefix: "../outside/")
      }
        .to(raise_error(Nob::Vault::InvalidPrefix, "prefix escapes the vault: ../outside/"))
    end

    it "raises InvalidPrefix when the prefix points to a file" do
      touch("notes.md")

      expect {
        described_class.list(vault, prefix: "notes.md")
      }
        .to(raise_error(Nob::Vault::InvalidPrefix))
    end
  end

  describe ".files" do
    it "lists every file regardless of extension, sorted, skipping directories and dot-directories" do
      touch("a.md")
      touch("img/diagram.png")
      touch(".obsidian/app.json")
      FileUtils.mkdir_p(File.join(vault, "empty"))

      expect(described_class.files(vault)).to(eq(["a.md", "img/diagram.png"]))
    end
  end

  describe ".relative_path" do
    it "takes a relative path as relative to the vault" do
      expect(described_class.relative_path(vault, "daily/x.md")).to(eq("daily/x.md"))
      expect(described_class.relative_path(vault, "./daily/x.md")).to(eq("daily/x.md"))
    end

    it "turns an absolute path inside the vault into a vault-relative one, even if the file does not exist" do
      expect(described_class.relative_path(vault, File.join(vault, "daily", "new.md"))).to(eq("daily/new.md"))
    end

    it "keeps a leading ~ in a relative path as part of the file name" do
      expect(described_class.relative_path(vault, "~draft.md")).to(eq("~draft.md"))
      expect(described_class.relative_path(vault, "daily/~x.md")).to(eq("daily/~x.md"))
    end

    it "raises InvalidPath for a path outside the vault" do
      expect { described_class.relative_path(vault, "../x.md") }.to(
        raise_error(Nob::Vault::InvalidPath, "path is outside the vault: ../x.md")
      )
      expect { described_class.relative_path(vault, "/etc/hosts") }.to(
        raise_error(Nob::Vault::InvalidPath, "path is outside the vault: /etc/hosts")
      )
    end

    context("when the vault is reached through a symlink") do
      let(:real) { Dir.mktmpdir("nob-real") }
      let(:link) { File.join(vault, "link") }

      before { File.symlink(real, link) }
      after { FileUtils.remove_entry(real) }

      it "accepts an absolute path under the real directory" do
        path = File.join(File.realpath(real), "daily", "x.md")

        expect(described_class.relative_path(link, path)).to(eq("daily/x.md"))
      end

      it "accepts a path reached through another symlink to the vault" do
        other = Dir.mktmpdir("nob-other")
        alias_path = File.join(other, "alias")
        File.symlink(real, alias_path)

        expect(described_class.relative_path(real, File.join(alias_path, "daily", "new.md"))).to(eq("daily/new.md"))
      ensure
        FileUtils.remove_entry(other)
      end

      it "accepts a path through a symlinked directory inside the vault" do
        FileUtils.mkdir_p(File.join(real, "daily"))
        File.symlink(File.join(real, "daily"), File.join(real, "today"))

        expect(described_class.relative_path(real, File.join(real, "today", "x.md"))).to(eq("today/x.md"))
      end

      it "still accepts a path under the symlink itself" do
        expect(described_class.relative_path(link, File.join(link, "x.md"))).to(eq("x.md"))
      end
    end
  end

  describe ".name_key" do
    it "folds case and normalizes to NFC" do
      expect(described_class.name_key("Plan")).to(eq(described_class.name_key("PLAN")))
      expect(described_class.name_key("\u30AB\u3099")).to(eq(described_class.name_key("\u30AC")))
    end

    it "matches a name given as bytes, as ARGV is under LANG=C" do
      expect(described_class.name_key("計画".b)).to(eq(described_class.name_key("計画")))
    end

    it "does not raise for a name that is not valid UTF-8" do
      expect { described_class.name_key("bad\xFF.md".b) }.not_to(raise_error)
      expect { described_class.name_key("bad\xFF.md".dup.force_encoding("UTF-8")) }.not_to(raise_error)
    end

    it "keeps different names apart" do
      expect(described_class.name_key("Plan")).not_to(eq(described_class.name_key("Plans")))
    end
  end

  describe ".find_notes" do
    it "returns every note whose file name matches the title, sorted by path" do
      touch("projects/Plan.md")
      touch("archive/Plan.md")
      touch("Planning.md")

      expect(described_class.find_notes(vault, "Plan")).to(eq(["archive/Plan.md", "projects/Plan.md"]))
    end

    it "matches the title case-insensitively" do
      touch("projects/Plan.md")

      expect(described_class.find_notes(vault, "plan")).to(eq(["projects/Plan.md"]))
    end

    it "matches a decomposed (NFD) file name against a composed (NFC) title" do
      touch("\u30AB\u3099\u30A4\u30C9.md")

      expect(described_class.find_notes(vault, "\u30AC\u30A4\u30C9")).to(eq(["\u30AB\u3099\u30A4\u30C9.md"]))
    end

    it "returns an empty array when no note matches" do
      touch("a.md")

      expect(described_class.find_notes(vault, "missing")).to(eq([]))
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

  describe ".read" do
    it "reads a file as UTF-8" do
      abs = touch("jp.md", "計画")

      expect(described_class.read(abs)).to(eq("計画"))
      expect(described_class.read(abs).encoding).to(eq(Encoding::UTF_8))
    end

    it "strips a UTF-8 BOM" do
      abs = touch("bom.md")
      File.binwrite(abs, "\xEF\xBB\xBF---\n".b)

      expect(described_class.read(abs)).to(eq("---\n"))
    end

    it "raises InvalidEncoding for a file that is not valid UTF-8" do
      abs = touch("bad.md")
      File.binwrite(abs, "\xFF".b)

      expect { described_class.read(abs) }.to(raise_error(Nob::Vault::InvalidEncoding, "invalid UTF-8 in #{abs}"))
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

    it "parses the given text instead of reading the file again" do
      abs = touch("a.md", "on disk")

      expect(described_class.frontmatter(abs, "---\ntitle: given\n---\nbody\n")).to(
        eq(frontmatter: {"title" => "given"}, body: "body\n")
      )
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
