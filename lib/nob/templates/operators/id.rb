module Nob
  module Templates
    module Operators
      class Id < Base
        def initialize(fmt)
          unless fmt.nil?
            raise UndefinedVariable, "id does not accept format: #{fmt}"
          end
          super
        end

        def call(title:, now:)
          now.strftime("%Y%m%d%H%M%S")
        end
      end
    end
  end
end
