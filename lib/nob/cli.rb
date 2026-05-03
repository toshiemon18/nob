require "thor"

module Nob
  class Cli < Thor
    def self.exit_on_failure? = true

    desc "version", "Print nob version"
    def version
      puts Nob::VERSION
    end

    desc "create TITLE", "Create a new note under the vault"
    method_option :dir, aliases: "-d", type: :string, desc: "Subdirectory under vault (e.g. projects, daily/2026)"
    method_option :force, aliases: "-f", type: :boolean, default: false, desc: "Backup existing file and recreate"
    def create(title)
      config = Nob::Config.load
      result = Nob::Notes::Creator.create(
        title: title,
        vault: config.vault,
        dir: options[:dir],
        force: options[:force]
      )
      puts "Created: #{result.path}"
      puts "Backup : #{result.backup_path}" if result.backup_path
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    desc "show TITLE", "Print path, size, character count, and frontmatter for a note"
    def show(title)
      config = Nob::Config.load
      detail = Nob::Notes::Viewer.show(vault: config.vault, title: title)
      puts "Path     : #{detail.note.relative_path}"
      puts "Size     : #{format_size(detail.size)}"
      puts "Chars    : #{detail.chars}"
      unless detail.frontmatter.empty?
        puts "---frontmatter---"
        key_width = detail.frontmatter.keys.map(&:to_s).map(&:length).max
        detail.frontmatter.each do |key, value|
          puts "#{key.to_s.ljust([key_width, 8].max)} : #{value}"
        end
      end
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    desc "config", "View or edit the config file (use -e/--path/--show)"
    method_option :edit, aliases: "-e", type: :boolean, default: false, desc: "Open config in editor"
    method_option :path, aliases: "-p", type: :boolean, default: false, desc: "Print config file path"
    method_option :show, aliases: "-s", type: :boolean, default: false, desc: "Print config file contents"
    def config
      flags = [options[:edit], options[:path], options[:show]].count(true)
      if flags > 1
        warn "Error: specify only one of -e/--path/--show"
        exit 1
      end
      if flags.zero?
        warn "Usage: nob config -e"
        exit 1
      end
      path = Nob::Config.default_path
      Nob::Config.ensure_exists(path)
      if options[:edit]
        Nob::Config::Editor.open(path: path)
      elsif options[:path]
        puts path
      elsif options[:show]
        print File.read(path)
      end
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    desc "list", "List notes under the vault"
    method_option :prefix, type: :string, desc: "Filter by vault-relative subdirectory (e.g. daily, projects/2026)"
    def list
      config = Nob::Config.load
      entries = Nob::Notes::Lister.list(vault: config.vault, prefix: options[:prefix])
      entries.each { |entry| puts entry.relative_path }
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    no_commands do
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
