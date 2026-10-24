module Nob
  module Links
    # リンク先を vault のファイルに解決する。ファイルシステムには触れない
    class Resolver
      # @param files [Array<String>] vault 内の全ファイルの vault 相対パス
      def initialize(files)
        @files = files
      end

      # @param target [String] リンク先の名前（Link#target）
      # @param from [String] リンクを書いたノートの vault 相対パス
      # (String, from: String) -> Resolution
      def resolve(target, from:)
        key = Nob::Vault.name_key(target)
        candidates = @files.select do |rel|
          if target.include?("/")
            names(rel).any? { |name| name == key || name.end_with?("/#{key}") }
          else
            names(File.basename(rel)).include?(key)
          end
        end
        return Resolution.new(status: :unresolved, paths: []) if candidates.empty?

        Resolution.new(status: :resolved, paths: candidates)
      end

      private

      # path に当たるリンク先の鍵。ノートは .md の有無どちらでも当たる
      def names(path)
        [path, path.delete_suffix(".md")].uniq.map { |name| Nob::Vault.name_key(name) }
      end
    end
  end
end
