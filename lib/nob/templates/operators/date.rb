module Nob
  module Templates
    module Operators
      class Date < Base
        def call(title:, now:)
          case fmt
          when nil         then now.strftime("%Y-%m-%d")
          when "timestamp" then now.to_i.to_s
          else                  now.strftime(fmt)
          end
        end
      end
    end
  end
end
