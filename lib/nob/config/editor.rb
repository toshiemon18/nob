require "shellwords"

module Nob
  class Config
    class Editor
      DEFAULT = "vi"

      def self.resolve(env: ENV)
        raw = env["EDITOR"].to_s.strip
        raw.empty? ? DEFAULT : raw
      end

      def self.open(path:, env: ENV, runner: Kernel)
        editor = resolve(env: env)
        cmd = "#{editor} #{Shellwords.escape(path)}"
        result = runner.system(cmd)
        case result
        when nil
          raise Nob::Error, "failed to launch editor (#{editor}) for #{path}"
        when false
          raise Nob::Error, "editor (#{editor}) exited with non-zero status for #{path}"
        end
      end
    end
  end
end
