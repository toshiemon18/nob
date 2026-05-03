module Nob
  module Templates
    module Operators
      class Title < Base
        def initialize(fmt)
          unless fmt.nil?
            raise UndefinedVariable, "title does not accept format: #{fmt}"
          end
          super
        end

        def call(title:, now:)
          title
        end
      end
    end
  end
end
