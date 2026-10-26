module Nob
  module Links
    # リンク先を vault のファイルに解決する。ファイルシステムには触れない
    class Resolver
      # @param files [Array<String>] vault 内の全ファイルの vault 相対パス
      def initialize(files)
        # 照合の鍵はファイルごとに 1 回だけ作る。この実行の間だけメモリに持つ
        # / を含まないリンクはファイル名の鍵から引き、/ を含むリンクは [パス, パスの鍵] を順に調べる
        @by_basename = Hash.new { |hash, key| hash[key] = [] }
        @by_path = files.map do |rel|
          names(File.basename(rel)).each { |key| @by_basename[key] << rel }
          [rel, names(rel)]
        end
      end

      # @param target [String] リンク先の名前（Link#target）
      # @param from [String] リンクを書いたノートの vault 相対パス
      # (String, from: String) -> Resolution
      def resolve(target, from:)
        key = Nob::Vault.name_key(target)
        candidates = if target.include?("/")
          @by_path.filter_map do |rel, path_keys|
            rel if path_keys.any? { |name| name == key || name.end_with?("/#{key}") }
          end
        else
          @by_basename.fetch(key, [])
        end

        return Resolution.new(status: :unresolved, paths: []) if candidates.empty?

        by_distance = candidates.group_by { |rel| distance(from, rel) }
        nearest = by_distance.fetch(by_distance.keys.min).sort
        Resolution.new(status: nearest.size == 1 ? :resolved : :ambiguous, paths: nearest)
      end

      private

      # 2 つのファイルのディレクトリ間の距離。共通の祖先まで上がる段数と、そこから下る段数の和
      # ディレクトリ名も、ファイル名と同じく name_key で比べる
      def distance(from, to)
        from_dirs = dirs(from)
        to_dirs = dirs(to)
        common = from_dirs.zip(to_dirs).take_while { |a, b| a == b }.size
        (from_dirs.size - common) + (to_dirs.size - common)
      end

      def dirs(path)
        (File.dirname(path).split("/") - ["."]).map { |dir| Nob::Vault.name_key(dir) }
      end

      # path に当たるリンク先の鍵。ノートは .md の有無どちらでも当たる
      def names(path)
        [path, path.delete_suffix(".md")].uniq.map { |name| Nob::Vault.name_key(name) }
      end
    end
  end
end
