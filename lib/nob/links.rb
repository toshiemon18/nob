module Nob
  module Links
    # 本文中の 1 つのリンク
    # @!attribute raw    本文に書いたとおりの文字列（"![[Plan|計画]]"）
    # @!attribute target リンク先の名前（"|" と "#" より前）
    # @!attribute line   ファイル先頭からの行番号
    Link = Data.define(:raw, :target, :line)

    # リンク先の解決結果
    # @!attribute status :resolved / :unresolved / :ambiguous
    # @!attribute paths  解決したパス（:ambiguous なら候補すべて）。vault 相対
    Resolution = Data.define(:status, :paths)

    PATTERN = /!?\[\[([^\[\]\n]+)\]\]/
    FENCE = /\A {0,3}(`{3,}|~{3,})/
    INLINE_CODE = /(?<!`)(`+)(?!`).+?(?<!`)\1(?!`)/

    # ノートの全文からリンクを取り出す。名前が空のリンク（[[#見出し]] など）は除く。
    # frontmatter、フェンスで囲んだコードブロック、インラインコードの中は無視する
    # (String) -> Array[Link]
    def self.extract(text)
      lines = text.lines
      fence = nil
      lines.each_with_index.drop(body_start(lines)).flat_map do |line, index|
        if fence
          fence = nil if line.match?(/\A {0,3}#{Regexp.escape(fence[0])}{#{fence.length},}\s*\z/)
          next []
        end

        # バッククォートのフェンスは、後ろにバッククォートを書けない（書けば同じ行で閉じるインラインコード）
        if (opening = line[FENCE, 1]) && !(opening.start_with?("`") && line.sub(FENCE, "").include?("`"))
          fence = opening
          next []
        end

        links_in(line.gsub(INLINE_CODE, ""), index + 1)
      end
    end

    # text がちょうど 1 つのリンク（前後の空白は除く）なら、その Link を返す。それ以外は nil
    # (String) -> Link?
    def self.parse(text)
      stripped = text.strip
      links = extract(stripped)
      links.first if links.size == 1 && links.first.raw == stripped
    end

    # 本文が始まる行の index。先頭行が --- で、閉じの --- があれば frontmatter とみなす
    def self.body_start(lines)
      return 0 unless lines.first&.chomp == "---"

      closing = lines.each_with_index.drop(1).find { |line, _| line.chomp == "---" }
      closing ? closing[1] + 1 : 0
    end

    def self.links_in(line, number)
      line.to_enum(:scan, PATTERN).filter_map do
        match = Regexp.last_match
        # 表の中では Obsidian が別名の区切りを \| と書く
        target = match[1].split(/\\?\||#/, 2).first.to_s.strip
        Link.new(raw: match[0], target: target, line: number) unless target.empty?
      end
    end

    private_class_method :body_start, :links_in
  end
end
