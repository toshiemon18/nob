require "date"
require "thor"
require "yaml"

module Nob
  class Cli < Thor
    def self.exit_on_failure? = true

    desc "version", "Print nob version"
    def version
      puts(Nob::VERSION)
    end

    desc "create TITLE", "Create a new note under the vault"
    method_option :dir, aliases: "-d", type: :string, desc: "Subdirectory under vault (e.g. projects, daily/2026)"
    method_option :force, aliases: "-f", type: :boolean, default: false, desc: "Backup existing file and recreate"
    def create(title)
      config = Nob::Config.load
      path = Nob::Vault.path_for(config.vault, options[:dir], "#{title}.md")

      backup_path = nil
      if Nob::Vault.exists?(path)
        unless options[:force]
          raise Nob::Error, "Note already exists: #{path}"
        end

        backup_path = Nob::Vault.backup(path)
      end

      Nob::Vault.write(path, render_create_content(title, Date.today))
      puts(format_write_result(path, backup_path, recreated: !backup_path.nil?))
    end

    desc "show TITLE", "Print path, size, character count, and frontmatter for a note"
    def show(title)
      config = Nob::Config.load
      relative = resolve_title!(config.vault, title)
      absolute = Nob::Vault.path_for(config.vault, relative)
      parsed = Nob::Vault.frontmatter(absolute)

      puts("Path     : #{relative}")
      puts("Size     : #{format_size(Nob::Vault.size(absolute))}")
      puts("Chars    : #{parsed[:body].length}")
      print_frontmatter(parsed[:frontmatter])
    end

    desc "config", "View or edit the config file (use -e/--path/--show)"
    method_option :edit, aliases: "-e", type: :boolean, default: false, desc: "Open config in editor"
    method_option :path, aliases: "-p", type: :boolean, default: false, desc: "Print config file path"
    method_option :show, aliases: "-s", type: :boolean, default: false, desc: "Print config file contents"
    def config
      flags = [options[:edit], options[:path], options[:show]].count(true)
      if flags > 1
        warn("Error: specify only one of -e/--path/--show")
        exit(1)
      end

      if flags.zero?
        warn("Error: specify -e/--path/--show (use -h for usage)")
        exit(1)
      end

      path = Nob::Config.default_path
      Nob::Config.ensure_exists(path)
      if options[:edit]
        Nob::Config::Editor.open(path: path)
      elsif options[:path]
        puts(path)
      elsif options[:show]
        print(File.read(path))
      end
    end

    desc "daily", "Create today's daily note"
    method_option :force, aliases: "-f", type: :boolean, default: false, desc: "Backup existing and recreate"
    def daily
      config = Nob::Config.load
      settings = config.daily_settings
      if settings.template_path.nil?
        warn("Warning: no daily-note template configured ([dailyNote].template); creating an empty file.")
      end

      now = Time.now
      date_str = now.strftime(settings.file_name_format)
      path = Nob::Vault.path_for(config.vault, settings.base_path, "#{date_str}.md")

      backup_path = nil
      recreated = false
      if Nob::Vault.exists?(path)
        if options[:force]
          backup_path = Nob::Vault.backup(path, now: now)
          recreated = true
        elsif Nob::Vault.size(path) > 0
          puts("Already exists: #{path}")
          return
        else
          recreated = true
        end
      end

      content = if settings.template_path.nil?
        ""
      else
        Nob::Templates.render(title: date_str, now: now, path: settings.template_path)
      end

      Nob::Vault.write(path, content)
      puts(format_write_result(path, backup_path, recreated: recreated))
    end

    desc "list", "List notes under the vault"
    method_option :prefix, type: :string, desc: "Filter by vault-relative subdirectory (e.g. daily, projects/2026)"
    def list
      config = Nob::Config.load
      Nob::Vault.list(config.vault, prefix: options[:prefix]).each { |rel| puts(rel) }
    end

    no_commands do
      def invoke_command(command, *args)
        super
      rescue Nob::Error => e
        warn("Error: #{e.message}")
        exit(1)
      end

      def render_create_content(title, date)
        front_matter = YAML.dump({"title" => title, "date" => date})
        "#{front_matter}---\n\n"
      end

      def resolve_title!(vault, title)
        matches = Nob::Vault.list(vault).select { |rel| File.basename(rel, ".md") == title }
        raise Nob::Error, "note not found: #{title}" if matches.empty?

        if matches.size > 1
          sorted = matches.sort_by { |m| [File.basename(m), m] }
          raise Nob::Error, "multiple notes match \"#{title}\": #{sorted.join(", ")}"
        end

        matches.first
      end

      def format_write_result(path, backup_path, recreated:)
        if recreated
          backup_path ? "Recreated: #{path} (backup: #{backup_path})" : "Recreated: #{path}"
        else
          "Created: #{path}"
        end
      end

      def print_frontmatter(frontmatter)
        return if frontmatter.empty?

        puts("---frontmatter---")
        key_width = frontmatter.keys.map(&:to_s).map(&:length).max
        frontmatter.each do |key, value|
          puts("#{key.to_s.ljust([key_width, 8].max)} : #{value}")
        end
      end

      def format_size(bytes)
        kb = 1024
        mb = kb * 1024
        if bytes < kb
          "#{bytes}B"
        elsif bytes < mb
          "#{(bytes.to_f / kb).round(1)}KB"
        else
          "#{(bytes.to_f / mb).round(1)}MB"
        end
      end
    end
  end
end
