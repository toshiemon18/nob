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

    it "documents a [dailyNote] example that matches DAILY_DEFAULTS when uncommented" do
      uncommented = described_class::DEFAULT_CONTENT
        .lines
        .grep(/^# (\[dailyNote\]$|basePath |fileNameFormat )/)
        .map { |line| line.delete_prefix("# ") }
        .join

      expect(TomlRB.parse(uncommented)["dailyNote"]).to(eq(described_class::DAILY_DEFAULTS))
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
      expect(daily.template_path).to(be_nil)
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
      expect(daily.template_path).to(eq(File.join(vault, "templates/daily.md")))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "rejects a template path that escapes the vault, naming the config key" do
      vault = Dir.mktmpdir("nob-vault")
      contents = <<~TOML
        vault = "#{vault}"
        [dailyNote]
        template = "../tpl.md"
      TOML
      config, cfg_dir = write_config(contents)

      expect { config.daily_settings }.to(
        raise_error(
          Nob::Config::InvalidTemplatePath,
          "template path escapes the vault: ../tpl.md ([dailyNote].template)"
        )
      )
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "rejects an absolute template path, naming the config key" do
      vault = Dir.mktmpdir("nob-vault")
      contents = <<~TOML
        vault = "#{vault}"
        [dailyNote]
        template = "/etc/nob/daily.md"
      TOML
      config, cfg_dir = write_config(contents)

      expect { config.daily_settings }.to(
        raise_error(
          Nob::Config::InvalidTemplatePath,
          "template path must be relative to the vault: /etc/nob/daily.md ([dailyNote].template)"
        )
      )
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

      expect(config.note_settings.template_path).to(be_nil)
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "resolves [note].template relative to the vault" do
      vault = Dir.mktmpdir("nob-vault")
      config, cfg_dir = write_config(
        <<~TOML
          vault = "#{vault}"
          [note]
          template = "templates/note.md"
        TOML
      )

      expect(config.note_settings.template_path).to(eq(File.join(vault, "templates/note.md")))
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end

    it "rejects a [note].template that escapes the vault, naming the config key" do
      vault = Dir.mktmpdir("nob-vault")
      config, cfg_dir = write_config(
        <<~TOML
          vault = "#{vault}"
          [note]
          template = "../note.md"
        TOML
      )

      expect { config.note_settings }.to(
        raise_error(Nob::Config::InvalidTemplatePath, "template path escapes the vault: ../note.md ([note].template)")
      )
    ensure
      FileUtils.remove_entry(cfg_dir) if cfg_dir
      FileUtils.remove_entry(vault) if vault
    end
  end

  describe "#resolve_template" do
    let(:vault) { Dir.mktmpdir("nob-vault") }
    let(:cfg_dir) { Dir.mktmpdir("nob-cfg") }
    let(:config) do
      path = File.join(cfg_dir, "config.toml")
      File.write(path, "vault = \"#{vault}\"\n")
      described_class.load(path: path)
    end

    after do
      FileUtils.remove_entry(vault)
      FileUtils.remove_entry(cfg_dir)
    end

    it "returns nil for a blank value" do
      expect(config.resolve_template("", source: "--template")).to(be_nil)
      expect(config.resolve_template(nil, source: "--template")).to(be_nil)
    end

    it "resolves a vault-relative path" do
      expect(config.resolve_template("tpl/note.md", source: "--template")).to(eq(File.join(vault, "tpl/note.md")))
    end

    it "names the given source in the error" do
      expect { config.resolve_template("../../x.md", source: "--template") }.to(
        raise_error(Nob::Config::InvalidTemplatePath, "template path escapes the vault: ../../x.md (--template)")
      )
    end

    it "is a Nob::Error so the CLI reports it" do
      expect(Nob::Config::InvalidTemplatePath.ancestors).to(include(Nob::Error))
    end
  end
end
