module Nob
  module Links
    # リンク先を vault のファイルに解決する。ファイルシステムには触れない
    class Resolver
      # @param files [Array<String>] vault 内の全ファイルの vault 相対パス
      def initialize(files)
        # 照合の鍵はファイルごとに 1 回だけ作る。[パス, ファイル名の鍵, パスの鍵]
        @entries = files.map { |rel| [rel, names(File.basename(rel)), names(rel)] }
      end

      # @param target [String] リンク先の名前（Link#target）
      # @param from [String] リンクを書いたノートの vault 相対パス
      # (String, from: String) -> Resolution
      def resolve(target, from:)
        key = Nob::Vault.name_key(target)
        candidates = @entries.filter_map do |rel, basename_keys, path_keys|
          matched = if target.include?("/")
            path_keys.any? { |name| name == key || name.end_with?("/#{key}") }
          else
            basename_keys.include?(key)
          end

          rel if matched
        end

        return Resolution.new(status: :unresolved, paths: []) if candidates.empty?

        by_distance = candidates.group_by { |rel| distance(from, rel) }
        nearest = by_distance.fetch(by_distance.keys.min).sort
        Resolution.new(status: nearest.size == 1 ? :resolved : :ambiguous, paths: nearest)
      end

      private

      # 2 つのファイルのディレクトリ間の距離。共通の祖先まで上がる段数と、そこから下る段数の和
      def distance(from, to)
        from_dirs = File.dirname(from).split("/") - ["."]
        to_dirs = File.dirname(to).split("/") - ["."]
        common = from_dirs.zip(to_dirs).take_while { |a, b| a == b }.size
        (from_dirs.size - common) + (to_dirs.size - common)
      end

      # path に当たるリンク先の鍵。ノートは .md の有無どちらでも当たる
      def names(path)
        [path, path.delete_suffix(".md")].uniq.map { |name| Nob::Vault.name_key(name) }
      end
    end
  end
end
