module Nob
  module Templates
    module Operators
      REGISTRY = {
        "title" => Title,
        "date" => Date,
        "time" => Time,
        "id" => Id
      }.freeze

      def self.build(name:, fmt:)
        operator_class = REGISTRY.fetch(name) {
          raise UndefinedVariable, "unknown variable: #{name}"
        }
        operator_class.new(fmt)
      end
    end
  end
end
