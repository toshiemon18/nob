require "fileutils"
require "toml-rb"

module Nob
  class Config
    class InvalidTemplatePath < Nob::Error
    end

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
      # Template file (vault-relative or absolute). Without it, an empty note is created.
      # template = "templates/daily.md"
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

    DailySettings = Struct.new(:base_path, :file_name_format, :template_path, keyword_init: true)

    DAILY_DEFAULTS = {
      "basePath" => "daily/",
      "fileNameFormat" => "%Y-%m-%d"
    }.freeze

    def daily_settings
      raw = data["dailyNote"] || {}

      DailySettings.new(
        base_path: raw["basePath"] || DAILY_DEFAULTS["basePath"],
        file_name_format: raw["fileNameFormat"] || DAILY_DEFAULTS["fileNameFormat"],
        template_path: resolve_template(raw["template"], source: "[dailyNote].template")
      )
    end

    def resolve_template(raw, source:)
      return nil if raw.nil? || raw.to_s.empty?

      Nob::Vault.path_for(vault, raw.to_s)
    rescue Nob::Vault::InvalidPath => e
      raise InvalidTemplatePath, "template #{e.message} (#{source})"
    end

    private

    attr_reader :data

    def resolve_vault!
      raw = data["vault"].to_s
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
