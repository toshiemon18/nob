require "spec_helper"
require "tmpdir"
require "date"

RSpec.describe Nob::Notes::Creator do
  let(:vault) { Dir.mktmpdir("nob-vault") }
  let(:today) { Date.new(2026, 4, 27) }

  after { FileUtils.remove_entry(vault) }

  describe ".create" do
    it "creates a markdown file with frontmatter at vault root" do
      result = described_class.create(title: "My Note", vault: vault, today: today)

      expect(result.path).to eq(File.join(vault, "My Note.md"))
      expect(result.backup_path).to be_nil
      expect(File.read(result.path)).to eq(<<~MD)
        ---
        title: My Note
        date: 2026-04-27
        ---

      MD
    end

    it "places the note under --dir relative to vault" do
      result = described_class.create(title: "Plan", vault: vault, dir: "projects", today: today)

      expect(result.path).to eq(File.join(vault, "projects", "Plan.md"))
      expect(File.directory?(File.join(vault, "projects"))).to be true
    end

    it "creates nested directories under --dir" do
      result = described_class.create(title: "Daily", vault: vault, dir: "daily/2026/04", today: today)

      expect(result.path).to eq(File.join(vault, "daily/2026/04/Daily.md"))
    end

    it "raises AlreadyExists when the target file already exists" do
      described_class.create(title: "Dup", vault: vault, today: today)

      expect {
        described_class.create(title: "Dup", vault: vault, today: today)
      }.to raise_error(Nob::Notes::Creator::AlreadyExists)
    end

    it "backs up the existing file when force is true" do
      first = described_class.create(title: "Dup", vault: vault, today: today)
      File.write(first.path, "ORIGINAL")

      result = described_class.create(title: "Dup", vault: vault, force: true, today: today)

      expect(result.path).to eq(first.path)
      expect(result.backup_path).not_to be_nil
      expect(File.read(result.backup_path)).to eq("ORIGINAL")
      expect(File.read(result.path)).to include("title: Dup")
    end
  end
end
