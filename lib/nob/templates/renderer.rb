module Nob
  module Templates
    class Renderer
      def self.render(template, title:, now:)
        new(template).render(title: title, now: now)
      end

      def initialize(template)
        @tokens = Parser.parse(template)
      end

      def render(title:, now:)
        @tokens.map { |t|
          case t
          when Literal then t.text
          when Variable then t.operator.call(title: title, now: now)
          end
        }.join
      end
    end
  end
end
