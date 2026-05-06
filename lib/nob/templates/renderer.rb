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
        @tokens
          .map { |t|
            case t
            when Literal
              t.text
            when Variable
              t.operator.call(title: title, now: now)
            end
          }
          .join
      end
    end
  end
end
