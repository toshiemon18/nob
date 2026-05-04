module Nob
  module Templates
    module Loader
      def self.read(path)
        return nil if path.nil?
        unless File.exist?(path)
          raise Nob::Error, "template file not found: #{path}"
        end
        File.read(path)
      end
    end
  end
end
