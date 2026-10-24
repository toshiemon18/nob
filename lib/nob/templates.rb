module Nob
  module Templates
    class UndefinedVariable < Nob::Error
    end

    class ParseError < Nob::Error
    end

    class InvalidPath < Nob::Error
    end

    Literal = Struct.new(:text)
    Variable = Struct.new(:operator)

    # テンプレートをレンダリングした結果の文字列を返却する Facede メソッド
    # @param title [String] ファイルのタイトル
    # @param now [Time] 現在時刻
    # @param path [Pathname, String] テンプレートファイルのパス, text と同時に指定すると ArgumentError
    # @param text [String] テンプレートの文字列, path と同時に指定すると ArgumentError
    # @return [String] レンダリング結果の文字列
    # (String, Time, Pathname|String, String) -> String
    def self.render(title:, now:, path: nil, text: nil)
      raise ArgumentError, "specify path: or text:" if path.nil? && text.nil?
      raise ArgumentError, "specify only one of path: or text:" if path && text

      content = text
      if path
        raise Nob::Error, "template file not found: #{path}" unless File.exist?(path)

        content = File.read(path)
      end

      Renderer.render(content, title: title, now: now)
    end

    # テンプレートの指定を vault 内の絶対パスに解決する
    # @param vault [String] vault のルート
    # @param raw [String, nil] vault 相対のテンプレートパス
    # @param source [#to_s] 指定元（config のキーや CLI のオプション）。エラーメッセージに使う
    # @return [String, nil] 解決したパス。raw が空なら nil
    # (String, String?, source: _ToS) -> String?
    def self.locate(vault, raw, source:)
      return nil if raw.nil? || raw.to_s.empty?

      Nob::Vault.path_for(vault, raw.to_s)
    rescue Nob::Vault::InvalidPath => e
      raise InvalidPath, "template #{e.message} (#{source})"
    end
  end
end
