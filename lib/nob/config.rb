require "fileutils"
require "toml-rb"

module Nob
  class Config
    DEFAULT_CONTENT = <<~TOML
      # nob configuration

      # Vault root: absolute path to your Obsidian vault.
      # Edit this before using nob.
      vault = ""
    TOML

    attr_reader :path, :data

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
    end

    def vault
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

    DailySettings = Struct.new(:base_path, :file_name_format, :template_path)

    DAILY_DEFAULTS = {
      "basePath" => "daily/",
      "fileNameFormat" => "%Y-%m-%d"
    }.freeze

    def daily_settings
      raw = data["dailyNote"] || {}
      template = raw["template"]
      template_path = if template.nil? || template.to_s.empty?
        nil
      elsif File.absolute_path?(template)
        template
      else
        File.join(vault, template)
      end

      DailySettings.new(
        raw["basePath"] || DAILY_DEFAULTS["basePath"],
        raw["fileNameFormat"] || DAILY_DEFAULTS["fileNameFormat"],
        template_path
      )
    end
  end
end
