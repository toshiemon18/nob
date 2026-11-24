module Nob
  module Templates
    module Operators
      class Time < Base
        def initialize(fmt)
          super
          @time_format = Nob::TimeFormat.new(fmt) unless fmt.nil? || fmt == "timestamp"
        rescue Nob::TimeFormat::UnsupportedToken => e
          raise UndefinedVariable, e.message
        end

        def call(title:, now:)
          case fmt
          when nil
            now.strftime("%H:%M")
          when "timestamp"
            now.to_i.to_s
          else
            @time_format.format(now)
          end
        end
      end
    end
  end
end
