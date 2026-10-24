module Nob
  class Config
    # 設定ファイルの 1 つのキー。キー名、既定値、表示名を 1 か所で定義する
    Key = Data.define(:section, :name, :default) do
      def to_s
        section.nil? ? name : "[#{section}].#{name}"
      end

      # 設定ファイルを parse した Hash からこのキーの値を読む。
      # キーかセクションがなければ default を返す（空文字列はそのまま返す）
      def read(data)
        table = section.nil? ? data : (data[section] || {})
        value = table[name]
        value.nil? ? default : value
      end
    end
  end
end
