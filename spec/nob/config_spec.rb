require "spec_helper"
require "tmpdir"

RSpec.describe Nob::Config do
  describe Nob::Config::DailySettings do
    it "rejects positional initialization (keyword_init only)" do
      expect {
        described_class.new("daily/", "%Y-%m-%d", nil)
      }
        .to(raise_error(ArgumentError))
    end
  end

  describe "DEFAULT_CONTENT" do
    it "parses as TOML with the [dailyNote] example left commented out" do
      data = TomlRB.parse(described_class::DEFAULT_CONTENT)

      expect(data).to(eq({"vault" => ""}))
    end

    it "documents a [dailyNote] example that matches the Keys defaults when uncommented" do
      uncommented = described_class::DEFAULT_CONTENT
        .lines
        .grep(/^# (\[dailyNote\]$|basePath |fileNameFormat )/)
        .map { |line| line.delete_prefix("# ") }
        .join
      keys = [described_class::Keys::DAILY_BASE_PATH, described_class::Keys::DAILY_FILE_NAME_FORMAT]

      expect(TomlRB.parse(uncommented)["dailyNote"]).to(eq(keys.to_h { |key| [key.name, key.default] }))
    end
  end

  describe ".load" do
    def write_config(contents)
      dir = Dir.mktmpdir("nob-cfg")
      path = File.join(dir, "config.toml")
      File.write(path, contents)
      [path, dir]
    end

    it "raises Nob::Error eagerly when vault is unset" do
      path, cfg_dir = write_config("vault = \"\"\n")

      expect {
        described_class.load(path: path)
      }
        .to(raise_error(Nob::Error, /vault is not configured/))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
    end

    it "raises Nob::Error eagerly when vault directory is missing" do
      path, cfg_dir = write_config("vault = \"/nonexistent/nob-vault-xyz\"\n")

      expect {
        described_class.load(path: path)
      }
        .to(raise_error(Nob::Error, /vault directory does not exist/))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
    end

    it "freezes the resolved vault path so #vault stays valid even if the directory is removed afterwards" do
      vault = Dir.mktmpdir("nob-vault")
      path, cfg_dir = write_config("vault = \"#{vault}\"\n")

      config = described_class.load(path: path)
      resolved = config.vault
      FileUtils.remove_entry(vault)
      vault = nil

      expect(config.vault).to(eq(resolved))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "keeps the underlying data hash inaccessible so callers cannot desync it from @vault" do
      vault = Dir.mktmpdir("nob-vault")
      path, cfg_dir = write_config("vault = \"#{vault}\"\n")

      config = described_class.load(path: path)

      expect { config.data }.to(raise_error(NoMethodError, /private/))
    ensure
      FileUtils.remove_entry(vault) if vault
      FileUtils.remove_entry(cfg_dir) if cfg_dir
    end
  end

  describe "#daily_settings" do
    def write_config(contents)
      dir = Dir.mktmpdir("nob-cfg")
      path = File.join(dir, "config.toml")
      File.write(path, contents)
      [described_class.load(path: path), dir]
    end

    it "applies defaults when [dailyNote] is absent" do
      vault = Dir.mktmpdir("nob-vault")
      config, cfg_dir = write_config("vault = \"#{vault}\"\n")

      daily = config.daily_settings
      expect(daily.base_path).to(eq("daily/"))
      expect(daily.file_name_format).to(eq("%Y-%m-%d"))
      expect(daily.template).to(be_nil)
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "reads basePath / fileNameFormat / template when set" do
      vault = Dir.mktmpdir("nob-vault")
      contents = <<~TOML
        vault = "#{vault}"
        [dailyNote]
        basePath = "journal/"
        fileNameFormat = "%Y/%m/%d"
        template = "templates/daily.md"
      TOML
      config, cfg_dir = write_config(contents)

      daily = config.daily_settings
      expect(daily.base_path).to(eq("journal/"))
      expect(daily.file_name_format).to(eq("%Y/%m/%d"))
      expect(daily.template).to(eq("templates/daily.md"))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end
  end

  describe "#note_settings" do
    def write_config(contents)
      dir = Dir.mktmpdir("nob-cfg")
      path = File.join(dir, "config.toml")
      File.write(path, contents)
      [described_class.load(path: path), dir]
    end

    it "has no template when [note] is absent" do
      vault = Dir.mktmpdir("nob-vault")
      config, cfg_dir = write_config("vault = \"#{vault}\"\n")

      expect(config.note_settings.template).to(be_nil)
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "returns [note].template as written" do
      vault = Dir.mktmpdir("nob-vault")
      config, cfg_dir = write_config(
        <<~TOML
          vault = "#{vault}"
          [note]
          template = "templates/note.md"
        TOML
      )

      expect(config.note_settings.template).to(eq("templates/note.md"))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end
  end

  describe "#unknown_keys" do
    let(:vault) { Dir.mktmpdir("nob-vault") }

    after { FileUtils.remove_entry(vault) }

    def config_with(toml)
      described_class.new(path: "config.toml", data: TomlRB.parse("vault = \"#{vault}\"\n#{toml}"))
    end

    it "is empty when every key is known" do
      config = config_with(
        <<~TOML
          [dailyNote]
          basePath = "journal/"
          fileNameFormat = "%Y/%m/%d"
          template = "templates/daily.md"
          [note]
          template = "templates/note.md"
        TOML
      )

      expect(config.unknown_keys).to(eq([]))
    end

    it "names an unknown key inside a known section" do
      config = config_with("[note]\ntempalte = \"x.md\"\n")

      expect(config.unknown_keys).to(eq(["[note].tempalte"]))
    end

    it "names an unknown top-level key" do
      config = config_with("editor = \"vim\"\n")

      expect(config.unknown_keys).to(eq(["editor"]))
    end

    it "names each key of an unknown section" do
      config = config_with("[notes]\ntemplate = \"x.md\"\ndir = \"inbox\"\n")

      expect(config.unknown_keys).to(eq(["[notes].template", "[notes].dir"]))
    end
  end
end
