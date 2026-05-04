module Nob
  module Notes
    module Scanner
      def self.markdown_files(base)
        Dir.glob("**/*.md", base: base).sort
      end
    end
  end
end
