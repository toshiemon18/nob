require "fileutils"

module Nob
  module Notes
    class Daily
      Result = Struct.new(:path, :backup_path, :action, keyword_init: true)

      def self.create(vault:, daily_settings:, template_text: nil, now: Time.now, force: false)
        date_str = now.strftime(daily_settings.file_name_format)
        target_dir = File.join(vault, daily_settings.base_path)
        target_path = File.join(target_dir, "#{date_str}.md")

        backup_path = nil
        action =
          if File.exist?(target_path)
            if force
              backup_path = move_to_backup(target_path, now: now)
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
        File.write(target_path, render(template_text: template_text, title: date_str, now: now))
        Result.new(path: target_path, backup_path: backup_path, action: action)
      end

      def self.move_to_backup(path, now:)
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

      def self.render(template_text:, title:, now:)
        return "" if template_text.nil?
        Nob::Templates::Renderer.render(template_text, title: title, now: now)
      end
    end
  end
end
