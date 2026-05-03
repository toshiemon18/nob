module Nob
  module Entities
    # ノートを開いて読み込んだ時点の付随情報。
    # path 系は埋め込まれた Note に委ねる。
    NoteDetail = Struct.new(:note, :size, :chars, :frontmatter, keyword_init: true)
  end
end
