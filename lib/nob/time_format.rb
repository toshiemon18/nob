require "strscan"

module Nob
  # 日時の書式。% を含めば strftime、含まなければ moment.js の書式として読む
  class TimeFormat
    class UnsupportedToken < Nob::Error
    end

    # moment のトークンと、それに当たる strftime の書式
    MOMENT_TOKENS = {
      "YYYY" => "%Y",
      "YY" => "%y",
      "MM" => "%m",
      "M" => "%-m",
      "DD" => "%d",
      "D" => "%-d",
      "HH" => "%H",
      "H" => "%-H",
      "mm" => "%M",
      "ss" => "%S"
    }.freeze

    # 対応しないトークンは、ここで UnsupportedToken にする
    # (String) -> void
    def initialize(fmt)
      @strftime = fmt.include?("%") ? fmt : moment_to_strftime(fmt)
    end

    # (Time) -> String
    def format(time) = time.strftime(@strftime)

    private

    # moment の書式は % を含まないので、リテラルをそのまま strftime の書式に入れてよい
    def moment_to_strftime(fmt)
      s = StringScanner.new(fmt)
      out = +""
      until s.eos?
        if s.scan(/\[([^\]]*)\]/)
          out << s[1]
        elsif s.check(/\[/)
          raise UnsupportedToken, "unterminated [ in format: #{fmt}"
        elsif (letters = s.scan(/[A-Za-z]+/))
          out << letters_to_strftime(letters)
        else
          out << s.scan(/[^\[A-Za-z]+/)
        end
      end

      out
    end

    # 英字の連なりを同じ文字の連なりに分け（"YYYYMMDD" → YYYY, MM, DD）、どれもトークンのときだけ変換する。
    # moment のトークンはほぼ同じ文字の連なりなので、MMMM（月名）を MM 2 つと読まずに済む
    def letters_to_strftime(letters)
      tokens = letters.scan(/((.)\2*)/).map(&:first)
      unless tokens.all? { |token| MOMENT_TOKENS.key?(token) }
        raise UnsupportedToken, "unsupported format token: #{letters}"
      end

      tokens.map { |token| MOMENT_TOKENS.fetch(token) }.join
    end
  end
end
