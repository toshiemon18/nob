require "strscan"

module Nob
  module Templates
    class Parser
      def self.parse(template)
        new(template).parse
      end

      def initialize(template)
        @s = StringScanner.new(template)
        @line = 1
      end

      def parse
        tokens = []
        until @s.eos?
          chunk = @s.scan_until(/\{\{|\z/)
          if @s.matched == "{{"
            text = chunk.chomp("{{")
            advance_lines(text)
            tokens << Literal.new(text) unless text.empty?
            tokens << consume_variable
          else
            advance_lines(chunk)
            tokens << Literal.new(chunk) unless chunk.empty?
          end
        end
        tokens
      end

      private

      def consume_variable
        start_line = @line
        body = +""
        loop do
          if @s.eos?
            raise ParseError, "unterminated variable (line #{start_line})"
          elsif @s.scan(/\}\}/)
            break
          elsif @s.match?(/\{\{/)
            raise ParseError, "unexpected '{{' inside variable (line #{@line})"
          else
            ch = @s.getch
            body << ch
            advance_lines(ch)
          end
        end

        token_text = "{{#{body}}}"
        name, fmt = body.split(":", 2).map { |s| s&.strip }
        if name.nil? || name.empty?
          raise ParseError, "empty variable: #{token_text} (line #{start_line})"
        end

        begin
          op = Operators.build(name: name, fmt: fmt)
        rescue UndefinedVariable => e
          raise UndefinedVariable, "#{e.message}: #{token_text} (line #{start_line})"
        end

        Variable.new(op)
      end

      def advance_lines(text)
        @line += text.count("\n")
      end
    end
  end
end
