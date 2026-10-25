require "date"
require "did_you_mean"
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
    method_option(
      :template,
      aliases: "-t",
      type: :string,
      desc: "Vault-relative template path (overrides #{Nob::Config::Keys::NOTE_TEMPLATE})"
    )
    def create(title)
      config = load_config
      path = Nob::Vault.path_for(config.vault, options[:dir], "#{title}.md")
      now = Time.now
      raw_template, source = if options[:template]
        [options[:template], "--template"]
      else
        [config.note_settings.template, Nob::Config::Keys::NOTE_TEMPLATE]
      end

      template_path = Nob::Templates.locate(config.vault, raw_template, source: source)
      content = if template_path.nil?
        render_create_content(title, now.to_date)
      else
        Nob::Templates.render(title: title, now: now, path: template_path)
      end

      backup_path = nil
      if Nob::Vault.exists?(path)
        unless options[:force]
          raise Nob::Error, "Note already exists: #{path}"
        end

        backup_path = Nob::Vault.backup(path)
      end

      Nob::Vault.write(path, content)
      puts(format_write_result(path, backup_path, recreated: !backup_path.nil?))
    end

    desc "show TITLE", "Print path, size, character count, and frontmatter for a note"
    def show(title)
      config = load_config
      relative = resolve_title!(config.vault, title)
      absolute = Nob::Vault.path_for(config.vault, relative)
      parsed = Nob::Vault.frontmatter(absolute)

      puts("Path     : #{relative}")
      puts("Size     : #{format_size(Nob::Vault.size(absolute))}")
      puts("Chars    : #{parsed[:body].length}")
      print_frontmatter(parsed[:frontmatter])
      print_links(config.vault, relative, Nob::Links.extract(File.read(absolute)))
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
      config = load_config
      settings = config.daily_settings
      template_path = Nob::Templates.locate(config.vault, settings.template, source: Nob::Config::Keys::DAILY_TEMPLATE)
      if template_path.nil?
        warn(
          "Warning: no daily-note template configured (#{Nob::Config::Keys::DAILY_TEMPLATE}); creating an empty file."
        )
      end

      now = Time.now
      date_str = now.strftime(settings.file_name_format)
      path = Nob::Vault.path_for(config.vault, settings.base_path, "#{date_str}.md")

      exists = Nob::Vault.exists?(path)
      if exists && !options[:force] && Nob::Vault.size(path) > 0
        puts("Already exists: #{path}")
        return
      end

      content = if template_path.nil?
        ""
      else
        Nob::Templates.render(title: date_str, now: now, path: template_path)
      end

      backup_path = (Nob::Vault.backup(path, now: now) if exists && options[:force])
      recreated = exists

      Nob::Vault.write(path, content)
      puts(format_write_result(path, backup_path, recreated: recreated))
    end

    desc "list", "List notes under the vault"
    method_option :prefix, type: :string, desc: "Filter by vault-relative subdirectory (e.g. daily, projects/2026)"
    def list
      config = load_config
      Nob::Vault.list(config.vault, prefix: options[:prefix]).each { |rel| puts(rel) }
    end

    desc "links --unresolved", "List links that do not resolve to a single file, as path:line"
    method_option :unresolved, type: :boolean, default: false, desc: "List unresolved and ambiguous links"
    def links
      raise Nob::Error, "specify --unresolved" unless options[:unresolved]

      config = load_config
      resolver = Nob::Links::Resolver.new(Nob::Vault.files(config.vault))
      Nob::Vault.list(config.vault).each do |rel|
        text = File.read(Nob::Vault.path_for(config.vault, rel), encoding: "UTF-8")
        unless text.valid_encoding?
          warn("Warning: skipped #{rel}: invalid UTF-8")
          next
        end

        Nob::Links.extract(text).each do |link|
          resolution = resolver.resolve(link.target, from: rel)
          next if resolution.status == :resolved

          puts("#{rel}:#{link.line}: #{link.raw}#{format_unresolved_hint(resolution)}")
        end
      end
    end

    desc "resolve LINK", "Print the absolute path of the file a [[link]] resolves to (one line per candidate if ambiguous)"
    method_option :from, type: :string, desc: "Note the link is written in, absolute or vault-relative (default: the vault root)"
    def resolve(raw)
      config = load_config
      link = Nob::Links.parse(raw)
      raise Nob::Error, "expected a single [[link]]: #{raw}" unless link

      from = resolve_from!(config.vault, options[:from])
      resolution = Nob::Links::Resolver.new(Nob::Vault.files(config.vault)).resolve(link.target, from: from)
      resolution.paths.each { |rel| puts(File.join(config.vault, rel)) }
    end

    no_commands do
      def invoke_command(command, *args)
        super
      rescue Nob::Error => e
        warn("Error: #{e.message}")
        exit(1)
      end

      def load_config
        config = Nob::Config.load
        known = Nob::Config::Keys.all.map(&:to_s)
        spell_checker = DidYouMean::SpellChecker.new(dictionary: known)
        config.unknown_keys.each do |key|
          suggestion = spell_checker.correct(key).first
          hint = suggestion ? " (did you mean #{suggestion}?)" : ""
          warn("Warning: unknown config key #{key} in #{config.path}#{hint}")
        end

        config
      end

      def render_create_content(title, date)
        front_matter = YAML.dump({"title" => title, "date" => date})
        "#{front_matter}---\n\n"
      end

      def resolve_title!(vault, title)
        matches = Nob::Vault.find_notes(vault, title)
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

      # resolve の距離の起点（vault 相対パス）。省いたら vault 直下のノートから書いたものとして測る
      def resolve_from!(vault, path)
        return "." if path.nil?

        rel = Nob::Vault.relative_path(vault, path)
        raise Nob::Error, "--from is not a file: #{path}" if File.directory?(File.join(vault, rel))

        rel
      rescue Nob::Vault::InvalidPath => e
        raise Nob::Error, e.message.sub(/\Apath /, "--from ")
      end

      def print_frontmatter(frontmatter)
        return if frontmatter.empty?

        puts("---frontmatter---")
        key_width = frontmatter.keys.map(&:to_s).map(&:length).max
        frontmatter.each do |key, value|
          puts("#{key.to_s.ljust([key_width, 8].max)} : #{value}")
        end
      end

      def print_links(vault, from, links)
        distinct = links.uniq(&:raw)
        return if distinct.empty?

        resolver = Nob::Links::Resolver.new(Nob::Vault.files(vault))
        width = distinct.map { |link| link.raw.length }.max
        puts("---links---")
        distinct.each do |link|
          puts("#{link.raw.ljust(width)}  → #{format_resolution(resolver.resolve(link.target, from: from))}")
        end
      end

      def format_resolution(resolution)
        case resolution.status
        when :resolved
          resolution.paths.first
        when :unresolved
          "(unresolved)"
        when :ambiguous
          "(ambiguous: #{resolution.paths.join(", ")})"
        end
      end

      def format_unresolved_hint(resolution)
        resolution.status == :ambiguous ? " (ambiguous: #{resolution.paths.join(", ")})" : ""
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
