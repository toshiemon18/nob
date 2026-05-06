module Nob
  module Templates
    class UndefinedVariable < Nob::Error; end
    class ParseError < Nob::Error; end

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
      raise ArgumentError, "path or text must be provided" unless path || text
      raise ArgumentError, "path must exist" unless path && File.exist?(path)

      text ||= File.read(path)
      return "" if text.nil?

      Renderer.render(text, title: title, now: now)
    end
  end
end
