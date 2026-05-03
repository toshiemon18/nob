require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Notes::Daily do
  let(:now) { Time.new(2026, 5, 4, 9, 0, 0) }
  let(:settings) do
    Nob::Config::DailySettings.new("daily/", "%Y-%m-%d", nil)
  end

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
      result = described_class.create(vault: @vault, daily_settings: settings, template_text: nil, now: now)

      expect(result.action).to eq(:created)
      expect(result.path).to eq(daily_path)
      expect(result.backup_path).to be_nil
      expect(File.read(result.path)).to eq("")
    end

    it "renders the template when given" do
      template = "# {{title}}\n\nat {{date}}\n"
      result = described_class.create(vault: @vault, daily_settings: settings, template_text: template, now: now)

      expect(result.action).to eq(:created)
      expect(File.read(result.path)).to eq("# 2026-05-04\n\nat 2026-05-04\n")
    end

    it "creates the basePath directory if missing" do
      nested_settings = Nob::Config::DailySettings.new("journal/2026/", "%Y-%m-%d", nil)

      result = described_class.create(vault: @vault, daily_settings: nested_settings, template_text: nil, now: now)

      expect(result.path).to eq(File.join(@vault, "journal/2026/2026-05-04.md"))
      expect(File.exist?(result.path)).to be true
    end

    it "skips when the file exists with size > 0" do
      FileUtils.mkdir_p(File.dirname(daily_path))
      File.write(daily_path, "existing\n")

      result = described_class.create(vault: @vault, daily_settings: settings, template_text: "new", now: now)

      expect(result.action).to eq(:skipped)
      expect(File.read(daily_path)).to eq("existing\n")
    end

    it "recreates when the file exists with size 0" do
      FileUtils.mkdir_p(File.dirname(daily_path))
      File.write(daily_path, "")

      result = described_class.create(vault: @vault, daily_settings: settings, template_text: "fresh", now: now)

      expect(result.action).to eq(:recreated)
      expect(result.backup_path).to be_nil
      expect(File.read(daily_path)).to eq("fresh")
    end
  end
end
