module Nob
  module Links
    # 本文中の 1 つのリンク
    # @!attribute raw    本文に書いたとおりの文字列（"![[Plan|計画]]"）
    # @!attribute target リンク先の名前（"|" と "#" より前）
    # @!attribute line   ファイル先頭からの行番号
    Link = Data.define(:raw, :target, :line)

    PATTERN = /!?\[\[([^\[\]\n]+)\]\]/

    # ノートの全文からリンクを取り出す。名前が空のリンク（[[#見出し]] など）は除く
    # (String) -> Array[Link]
    def self.extract(text)
      text.each_line.with_index(1).flat_map do |line, number|
        line.to_enum(:scan, PATTERN).filter_map do
          match = Regexp.last_match
          target = match[1].split(/[|#]/, 2).first.to_s.strip
          Link.new(raw: match[0], target: target, line: number) unless target.empty?
        end
      end
    end
  end
end
