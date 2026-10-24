require "fileutils"
require "toml-rb"

module Nob
  class Config
    DEFAULT_CONTENT = <<~TOML
      # nob configuration

      # Vault root: absolute path to your Obsidian vault.
      # Edit this before using nob.
      vault = ""

      # Daily notes (`nob daily`). Uncomment to override the defaults.
      # Paths are relative to the vault; formats use strftime.
      # [dailyNote]
      # basePath = "daily/"
      # fileNameFormat = "%Y-%m-%d"
      # Template file (vault-relative). Without it, an empty note is created.
      # template = "templates/daily.md"

      # Notes created by `nob create`. Without a template, a title/date frontmatter is written.
      # `nob create --template PATH` overrides this for one invocation.
      # [note]
      # template = "templates/note.md"
    TOML

    attr_reader :path, :vault

    def self.default_path
      base = ENV["XDG_CONFIG_HOME"]
      base = File.join(Dir.home, ".config") if base.nil? || base.empty?
      File.join(base, "nob", "config.toml")
    end

    def self.load(path: default_path)
      ensure_exists(path)
      new(path: path, data: TomlRB.load_file(path))
    end

    def self.ensure_exists(path)
      return if File.exist?(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, DEFAULT_CONTENT)
    end

    def initialize(path:, data:)
      @path = path
      @data = data
      @vault = resolve_vault!
    end

    DailySettings = Struct.new(:base_path, :file_name_format, :template, keyword_init: true)

    def daily_settings
      DailySettings.new(
        base_path: Keys::DAILY_BASE_PATH.read(data),
        file_name_format: Keys::DAILY_FILE_NAME_FORMAT.read(data),
        template: Keys::DAILY_TEMPLATE.read(data)
      )
    end

    NoteSettings = Struct.new(:template, keyword_init: true)

    def note_settings
      NoteSettings.new(template: Keys::NOTE_TEMPLATE.read(data))
    end

    # 設定ファイルにあって Keys にないキーの表示名（"[note].tempalte" など）
    def unknown_keys
      known = Keys.all.map(&:to_s)
      present = data.flat_map do |name, value|
        if value.is_a?(Hash)
          value.keys.map { |key| Key.new(section: name, name: key, default: nil).to_s }
        else
          [Key.new(section: nil, name: name, default: nil).to_s]
        end
      end

      present - known
    end

    private

    attr_reader :data

    def resolve_vault!
      raw = Keys::VAULT.read(data).to_s
      if raw.empty?
        raise Nob::Error, "vault is not configured. Edit #{path} (or run `nob config -e`)."
      end

      expanded = File.expand_path(raw)
      unless File.directory?(expanded)
        raise Nob::Error, "vault directory does not exist: #{expanded}"
      end

      expanded
    end
  end
end
