require "fileutils"

module Nob
  module Notes
    class Daily
      Result = Struct.new(:path, :backup_path, :action, keyword_init: true)

      def self.create(vault:, base_path:, file_name_format:, template_path: nil, now: Time.now, force: false)
        date_str = now.strftime(file_name_format)
        target_dir = File.join(vault, base_path)
        target_path = File.join(target_dir, "#{date_str}.md")

        backup_path = nil
        action = if File.exist?(target_path)
          if force
            backup_path = Backup.move(target_path, now: now)
            :recreated
          elsif File.size(target_path) > 0
            :skipped
          else
            :recreated
          end
        else
          :created
        end

        return Result.new(path: target_path, backup_path: nil, action: :skipped) if action == :skipped

        FileUtils.mkdir_p(target_dir)
        content = if template_path.nil?
          ""
        else
          Nob::Templates.render(title: date_str, now:, path: template_path)
        end

        File.write(target_path, content)
        Result.new(path: target_path, backup_path: backup_path, action: action)
      end
    end
  end
end
