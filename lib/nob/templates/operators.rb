module Nob
  module Templates
    module Operators
      CLASS_NAME_PATTERN = /\A[a-z]+\z/

      def self.build(name:, fmt:)
        klass = lookup(name) or raise UndefinedVariable, "unknown variable: #{name}"
        klass.new(fmt)
      end

      def self.lookup(name)
        return nil unless name.match?(CLASS_NAME_PATTERN)
        const_name = name.capitalize.to_sym
        klass = begin
          const_get(const_name, false)
        rescue NameError
          return nil
        end
        (klass.is_a?(Class) && klass < Base) ? klass : nil
      end

      private_class_method :lookup
    end
  end
end
