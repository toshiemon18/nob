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

    class InvalidEncoding < Nob::Error
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

      relatives = Dir.glob("**/*.md", base: base).select { |rel| File.file?(File.join(base, rel)) }.sort
      return relatives if normalized.nil?

      relatives.map { |rel| File.join(normalized, rel) }
    end

    # vault 内の全ファイル（拡張子を問わない）の vault 相対パス。隠しディレクトリは含まない
    def self.files(vault)
      Dir.glob("**/*", base: vault).select { |rel| File.file?(File.join(vault, rel)) }.sort
    end

    # path を vault 相対パスにする。相対パスは vault を基準にする。path は存在しなくてよい
    # 字句的に vault の外なら、vault と path の両方を realpath にしてもう一度判定する（symlink 経由の vault）
    # (String, String) -> String
    def self.relative_path(vault, path)
      root = File.expand_path(vault)
      # 相対パスは vault と連結してから正規化する（File.expand_path(path, root) だと先頭の ~ を展開してしまう）
      absolute = File.expand_path(File.absolute_path?(path) ? path : File.join(root, path))
      return absolute.delete_prefix(root).delete_prefix(File::SEPARATOR) if within?(root, absolute)

      real_root = File.realpath(root) if File.exist?(root)
      real = realpath_existing(absolute)
      raise InvalidPath, "path is outside the vault: #{path}" unless real_root && within?(real_root, real)

      real.delete_prefix(real_root).delete_prefix(File::SEPARATOR)
    end

    # path のうち実在する一番深い祖先までを realpath にし、残り（まだないファイルなど）を足す
    def self.realpath_existing(path)
      existing = path
      rest = []
      until File.exist?(existing)
        rest.unshift(File.basename(existing))
        existing = File.dirname(existing)
      end

      File.join(File.realpath(existing), *rest)
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

    # ファイルを UTF-8 として読む。既定の外部エンコーディング（LANG）には左右されない
    def self.read(path)
      text = File.read(path, encoding: "UTF-8")
      raise InvalidEncoding, "invalid UTF-8 in #{path}" unless text.valid_encoding?

      text
    end

    # text を渡せば、ファイルを読み直さずにそれを解析する。path はエラーメッセージに使う
    def self.frontmatter(path, text = read(path))
      parsed = FrontMatterParser::Parser.new(:md, loader: YAML_LOADER).call(text)
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

    private_class_method :normalize_prefix, :validate_base!, :within?, :realpath_existing
  end
end
