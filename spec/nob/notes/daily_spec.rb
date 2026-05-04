require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Notes::Daily do
  let(:now) { Time.new(2026, 5, 4, 9, 0, 0) }
  let(:base_path) { "daily/" }
  let(:file_name_format) { "%Y-%m-%d" }

  around do |ex|
    Dir.mktmpdir("nob-vault") do |vault|
      @vault = vault
      ex.run
    end
  end

  def daily_path(date_str = "2026-05-04", base = "daily/")
    File.join(@vault, base, "#{date_str}.md")
  end

  describe ".create (normal mode)" do
    it "creates an empty file when template is nil and the file does not exist" do
      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: nil, now: now)

      expect(result.action).to eq(:created)
      expect(result.path).to eq(daily_path)
      expect(result.backup_path).to be_nil
      expect(File.read(result.path)).to eq("")
    end

    it "renders the template when given" do
      template = "# {{title}}\n\nat {{date}}\n"
      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: template, now: now)

      expect(result.action).to eq(:created)
      expect(File.read(result.path)).to eq("# 2026-05-04\n\nat 2026-05-04\n")
    end

    it "creates the basePath directory if missing" do
      result = described_class.create(vault: @vault, base_path: "journal/2026/", file_name_format: "%Y-%m-%d", template_text: nil, now: now)

      expect(result.path).to eq(File.join(@vault, "journal/2026/2026-05-04.md"))
      expect(File.exist?(result.path)).to be true
    end

    it "skips when the file exists with size > 0" do
      FileUtils.mkdir_p(File.dirname(daily_path))
      File.write(daily_path, "existing\n")

      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: "new", now: now)

      expect(result.action).to eq(:skipped)
      expect(File.read(daily_path)).to eq("existing\n")
    end

    it "recreates when the file exists with size 0" do
      FileUtils.mkdir_p(File.dirname(daily_path))
      File.write(daily_path, "")

      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: "fresh", now: now)

      expect(result.action).to eq(:recreated)
      expect(result.backup_path).to be_nil
      expect(File.read(daily_path)).to eq("fresh")
    end
  end

  describe ".create (force mode)" do
    it "behaves like normal mode when the file does not exist" do
      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: nil, now: now, force: true)

      expect(result.action).to eq(:created)
      expect(result.backup_path).to be_nil
    end

    it "moves an existing file to a timestamped backup and recreates it" do
      FileUtils.mkdir_p(File.dirname(daily_path))
      File.write(daily_path, "old content")

      result = described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: "new", now: now, force: true)

      expect(result.action).to eq(:recreated)
      expect(result.backup_path).to match(%r{/daily/2026-05-04\.backup-\d{8}-\d{6}\.md\z})
      expect(File.read(result.backup_path)).to eq("old content")
      expect(File.read(result.path)).to eq("new")
    end

    it "raises when the backup destination already exists (same-second collision)" do
      described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: nil, now: now)
      described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: "v1", now: now, force: true)

      expect {
        described_class.create(vault: @vault, base_path: base_path, file_name_format: file_name_format, template_text: "v2", now: now, force: true)
      }.to raise_error(Nob::Error, /backup target already exists/)
    end
  end
end
