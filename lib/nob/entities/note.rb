module Nob
  module Entities
    # vault 上に存在するノートを表す読み取り専用の値オブジェクト。
    # 作成オペレーションの結果は Nob::Notes::Creator::Result（path / backup_path）を使う。
    Note = Struct.new(:absolute_path, :relative_path, keyword_init: true)
  end
end
