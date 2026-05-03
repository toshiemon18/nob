module Nob
  class Config
    class Editor
      DEFAULT = "vi"

      def self.resolve(env: ENV)
        raw = env["EDITOR"].to_s.strip
        raw.empty? ? DEFAULT : raw
      end
    end
  end
end
