require "date"
require "fileutils"
require "front_matter_parser"

module Nob
  module Vault
    class InvalidPrefix < Nob::Error
    end

    class PrefixNotFound < Nob::Error
    end

    class InvalidFrontmatter < Nob::Error
    end

    YAML_LOADER = FrontMatterParser::Loader::Yaml.new(
      allowlist_classes: [Date, Time]
    )

    def self.path_for(vault, *segments)
      parts = [vault]
      segments.each do |seg|
        next if seg.nil? || seg.to_s.empty?
        parts << seg.to_s
      end

      File.join(*parts)
    end

    def self.exists?(path) = File.exist?(path)

    def self.size(path) = File.size(path)

    def self.write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def self.list(vault, prefix: nil)
      normalized = normalize_prefix(prefix, vault: vault)
      base = normalized ? File.join(vault, normalized) : vault
      validate_base!(base, normalized)

      relatives = Dir.glob("**/*.md", base: base).sort
      return relatives if normalized.nil?

      relatives.map { |rel| File.join(normalized, rel) }
    end

    def self.backup(path, now: Time.now)
      timestamp = now.strftime("%Y%m%d-%H%M%S")
      ext = File.extname(path)
      base = File.basename(path, ext)
      backup_path = File.join(File.dirname(path), "#{base}.backup-#{timestamp}#{ext}")
      if File.exist?(backup_path)
        raise Nob::Error, "backup target already exists: #{backup_path}"
      end

      FileUtils.mv(path, backup_path)
      backup_path
    end

    def self.frontmatter(path)
      parsed = FrontMatterParser::Parser.parse_file(path, loader: YAML_LOADER)
      {frontmatter: parsed.front_matter || {}, body: parsed.content}
    rescue Psych::SyntaxError => e
      raise InvalidFrontmatter, "invalid YAML frontmatter in #{path}: #{e.message}"
    end

    def self.normalize_prefix(prefix, vault:)
      return nil if prefix.nil? || prefix.empty?

      if File.absolute_path?(prefix)
        raise InvalidPrefix, "prefix must be relative to the vault: #{prefix}"
      end

      stripped = prefix.chomp("/")

      vault_real = File.realpath(vault)
      candidate = File.expand_path(stripped, vault_real)
      unless candidate == vault_real || candidate.start_with?("#{vault_real}#{File::SEPARATOR}")
        raise InvalidPrefix, "prefix escapes the vault: #{prefix}"
      end

      stripped
    end

    def self.validate_base!(base, normalized_prefix)
      return if normalized_prefix.nil?

      unless File.exist?(base)
        raise PrefixNotFound, "prefix directory not found: #{normalized_prefix}"
      end

      unless File.directory?(base)
        raise InvalidPrefix, "prefix must be a directory: #{normalized_prefix}"
      end
    end

    private_class_method :normalize_prefix, :validate_base!
  end
end
