require "spec_helper"
require "tmpdir"
require "fileutils"
require "date"

RSpec.describe Nob::Notes::Viewer do
  let(:vault) { Dir.mktmpdir("nob-vault") }

  after { FileUtils.remove_entry(vault) }

  def touch(relative_path, content = "")
    abs = File.join(vault, relative_path)
    FileUtils.mkdir_p(File.dirname(abs))
    File.write(abs, content)
    abs
  end

  describe ".show" do
    it "returns metadata for a single hit without frontmatter" do
      body = "hello world"
      abs = touch("README.md", body)

      detail = described_class.show(vault: vault, title: "README")

      expect(detail).to be_a(Nob::Entities::NoteDetail)
      expect(detail.note).to eq(Nob::Entities::Note.new(absolute_path: abs, relative_path: "README.md"))
      expect(detail.size).to eq(body.bytesize)
      expect(detail.chars).to eq(body.length)
      expect(detail.frontmatter).to eq({})
    end

    it "parses frontmatter and counts chars excluding the frontmatter block" do
      file = <<~MD
        ---
        title: My Note
        date: 2026-04-27
        ---

        body here
      MD
      touch("note.md", file)

      detail = described_class.show(vault: vault, title: "note")

      expect(detail.frontmatter).to eq("title" => "My Note", "date" => Date.new(2026, 4, 27))
      expect(detail.chars).to eq("body here\n".length)
    end

    it "finds a note nested under subdirectories by basename" do
      abs = touch("daily/2026/04/27.md", "deep")

      detail = described_class.show(vault: vault, title: "27")

      expect(detail.note.absolute_path).to eq(abs)
      expect(detail.note.relative_path).to eq("daily/2026/04/27.md")
    end

    it "does not treat title metacharacters as glob patterns" do
      touch("foo.md", "real")
      touch("bar.md", "real")

      # If "*" were interpreted as a glob, this would match both foo.md and bar.md.
      expect {
        described_class.show(vault: vault, title: "*")
      }.to raise_error(Nob::Notes::Viewer::NotFound)
    end

    it "ignores dotfiles and dot-directories when resolving the title" do
      touch(".hidden.md", "x")
      # basename "note" が title 一致するファイルをドットディレクトリ配下に置き、
      # ドット隠蔽がなければヒットするはずのケースで NotFound になることを確認する。
      touch(".cache/note.md", "x")

      expect {
        described_class.show(vault: vault, title: "hidden")
      }.to raise_error(Nob::Notes::Viewer::NotFound)
      expect {
        described_class.show(vault: vault, title: "note")
      }.to raise_error(Nob::Notes::Viewer::NotFound)
    end

    it "returns size 0 and chars 0 for a zero-byte file" do
      touch("empty.md", "")

      detail = described_class.show(vault: vault, title: "empty")

      expect(detail.size).to eq(0)
      expect(detail.chars).to eq(0)
      expect(detail.frontmatter).to eq({})
    end

    it "raises Ambiguous with candidate paths when multiple notes match" do
      touch("projects/Plan.md")
      touch("archive/Plan.md")

      expect {
        described_class.show(vault: vault, title: "Plan")
      }.to raise_error(Nob::Notes::Viewer::Ambiguous) { |e|
        expect(e.message).to include("archive/Plan.md")
        expect(e.message).to include("projects/Plan.md")
        expect(e.message.index("archive/Plan.md")).to be < e.message.index("projects/Plan.md")
      }
    end

    it "raises NotFound when no note matches the title" do
      touch("other.md")

      expect {
        described_class.show(vault: vault, title: "missing")
      }.to raise_error(Nob::Notes::Viewer::NotFound, /missing/)
    end

    it "raises InvalidFrontmatter when the YAML cannot be parsed" do
      file = <<~MD
        ---
        title: : : invalid
        - broken
        ---

        body
      MD
      touch("broken.md", file)

      expect {
        described_class.show(vault: vault, title: "broken")
      }.to raise_error(Nob::Notes::Viewer::InvalidFrontmatter)
    end

    it "preserves the YAML key order in the frontmatter Hash" do
      file = <<~MD
        ---
        zeta: 1
        alpha: 2
        mid: 3
        ---

        body
      MD
      touch("ordered.md", file)

      detail = described_class.show(vault: vault, title: "ordered")

      expect(detail.frontmatter.keys).to eq(%w[zeta alpha mid])
    end
  end
end
