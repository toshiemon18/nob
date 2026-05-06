require "fileutils"

module Nob
  module Notes
    class Backup
      def self.move(path, now: Time.now)
        timestamp = now.strftime("%Y%m%d-%H%M%S")
        ext = File.extname(path)
        base = File.basename(path, ext)
        backup_path = File.join(File.dirname(path), "#{base}.backup-#{timestamp}#{ext}")
        if File.exist?(backup_path)
          raise Nob::Error, "backup target already exists: #{backup_path}"
        end

        FileUtils.mv(path, backup_path)
        backup_path
      end
    end
  end
end
