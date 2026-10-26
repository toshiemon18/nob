require "spec_helper"

RSpec.describe Nob::Links::Resolver do
  def resolve(files, target, from: "note.md")
    described_class.new(files).resolve(target, from: from)
  end

  def resolved(*paths) = Nob::Links::Resolution.new(status: :resolved, paths: paths)

  def unresolved = Nob::Links::Resolution.new(status: :unresolved, paths: [])

  it "resolves a name to the note with that file name" do
    expect(resolve(["projects/Plan.md", "Planning.md"], "Plan")).to(eq(resolved("projects/Plan.md")))
  end

  it "matches names case-insensitively after NFC" do
    expect(resolve(["\u30AB\u3099\u30A4\u30C9.md"], "\u30AC\u30A4\u30C9")).to(
      eq(resolved("\u30AB\u3099\u30A4\u30C9.md"))
    )
    expect(resolve(["Plan.md"], "plan")).to(eq(resolved("Plan.md")))
  end

  it "treats a target ending in .md like the bare name" do
    expect(resolve(["projects/Plan.md"], "Plan.md")).to(eq(resolved("projects/Plan.md")))
  end

  it "resolves an attachment by its full file name" do
    expect(resolve(["img/diagram.png"], "diagram.png")).to(eq(resolved("img/diagram.png")))
  end

  it "does not match an attachment by its name without the extension" do
    expect(resolve(["img/diagram.png"], "diagram")).to(eq(unresolved))
  end

  it "resolves a note whose name contains a dot" do
    expect(resolve(["v1.2 notes.md"], "v1.2 notes")).to(eq(resolved("v1.2 notes.md")))
  end

  context("with a path in the target") do
    it "matches the end of the vault-relative path" do
      files = ["projects/Plan.md", "archive/Plan.md"]

      expect(resolve(files, "projects/Plan")).to(eq(resolved("projects/Plan.md")))
      expect(resolve(files, "projects/Plan.md")).to(eq(resolved("projects/Plan.md")))
    end

    it "matches a nested path suffix" do
      expect(resolve(["work/projects/Plan.md"], "projects/Plan")).to(eq(resolved("work/projects/Plan.md")))
    end

    it "matches only at directory boundaries" do
      expect(resolve(["myprojects/Plan.md"], "projects/Plan")).to(eq(unresolved))
    end
  end

  context("with several candidates") do
    def ambiguous(*paths) = Nob::Links::Resolution.new(status: :ambiguous, paths: paths)

    it "picks the candidate in the same directory" do
      files = ["daily/2026/Plan.md", "daily/Plan.md"]

      expect(resolve(files, "Plan", from: "daily/2026/a.md")).to(eq(resolved("daily/2026/Plan.md")))
    end

    it "picks the nearest by directories up plus directories down" do
      files = ["projects/Plan.md", "Plan.md"]

      expect(resolve(files, "Plan", from: "daily/2026/a.md")).to(eq(resolved("Plan.md")))
    end

    it "compares directories by case and NFC as it does names" do
      files = ["daily/Plan.md", "other/Plan.md", "\u30AC/Plan.md"]

      expect(resolve(files, "Plan", from: "Daily/a.md")).to(eq(resolved("daily/Plan.md")))
      expect(resolve(files, "Plan", from: "\u30AB\u3099/a.md")).to(eq(resolved("\u30AC/Plan.md")))
    end

    it "reports a tie for the nearest as ambiguous, listing the tied paths" do
      files = ["projects/Plan.md", "daily/Plan.md", "daily/2026/x/Plan.md"]

      expect(resolve(files, "Plan", from: "daily/2026/a.md")).to(eq(ambiguous("daily/2026/x/Plan.md", "daily/Plan.md")))
    end

    it "applies the same rule to path targets" do
      files = ["archive/projects/Plan.md", "projects/Plan.md"]

      expect(resolve(files, "projects/Plan", from: "archive/note.md")).to(eq(resolved("archive/projects/Plan.md")))
    end
  end

  it "reports a name with no matching note as unresolved" do
    expect(resolve(["a.md"], "missing")).to(eq(unresolved))
  end
end
