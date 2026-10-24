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

    class InvalidPath < Nob::Error
    end

    YAML_LOADER = FrontMatterParser::Loader::Yaml.new(
      allowlist_classes: [Date, Time]
    )

    def self.path_for(vault, *segments)
      relatives = segments.map(&:to_s).reject(&:empty?)
      absolute = relatives.find { |seg| File.absolute_path?(seg) }
      raise InvalidPath, "path must be relative to the vault: #{absolute}" if absolute

      path = File.join(vault, *relatives)
      unless within?(File.expand_path(vault), File.expand_path(path))
        raise InvalidPath, "path escapes the vault: #{File.join(*relatives)}"
      end

      path
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

    # ノート名やリンク先を照合するための鍵。NFC に正規化し、大文字と小文字を区別しない
    def self.name_key(name)
      name.unicode_normalize(:nfc).downcase(:fold)
    end

    # ファイル名（拡張子を除く）が title と一致するノートの vault 相対パス
    def self.find_notes(vault, title)
      key = name_key(title)
      list(vault).select { |rel| name_key(File.basename(rel, ".md")) == key }
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

      path_for(vault, prefix)
      prefix.chomp("/")
    rescue InvalidPath => e
      raise InvalidPrefix, e.message.sub(/\Apath /, "prefix ")
    end

    def self.within?(root, candidate)
      return true if candidate == root

      candidate.start_with?("#{root.chomp(File::SEPARATOR)}#{File::SEPARATOR}")
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

    private_class_method :normalize_prefix, :validate_base!, :within?
  end
end
