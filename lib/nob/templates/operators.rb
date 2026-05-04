module Nob
  module Templates
    module Operators
      def self.build(name:, fmt:)
        operator = case name
        when "title" then Title
        when "date" then Date
        when "time" then Time
        when "id" then Id
        else raise UndefinedVariable, "unknown variable: #{name}"
        end
        operator.new(fmt)
      end
    end
  end
end
