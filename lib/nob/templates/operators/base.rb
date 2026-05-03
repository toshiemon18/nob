module Nob
  module Templates
    module Operators
      class Base
        attr_reader :fmt

        def initialize(fmt)
          @fmt = fmt
        end

        def ==(other)
          other.class == self.class && other.fmt == fmt
        end

        def hash
          [self.class, fmt].hash
        end
      end
    end
  end
end
