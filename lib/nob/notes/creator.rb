require "date"
require "fileutils"
require "yaml"

module Nob
  module Notes
    class Creator
      class AlreadyExists < Nob::Error; end

      # 作成オペレーション結果。既存ノートの値オブジェクト Nob::Entities::Note とは別物。
      Result = Struct.new(:path, :backup_path, keyword_init: true)

      def self.create(title:, vault:, dir: nil, force: false, today: Date.today)
        target_dir = (dir.nil? || dir.to_s.empty?) ? vault : File.join(vault, dir)
        target_path = File.join(target_dir, "#{title}.md")

        backup_path = nil
        if File.exist?(target_path)
          unless force
            raise AlreadyExists, "Note already exists: #{target_path}"
          end
          backup_path = Backup.move(target_path)
        end

        FileUtils.mkdir_p(target_dir)
        File.write(target_path, render(title: title, date: today))

        Result.new(path: target_path, backup_path: backup_path)
      end

      def self.render(title:, date:)
        front_matter = YAML.dump({"title" => title, "date" => date})
        "#{front_matter}---\n\n"
      end

      private_class_method :render
    end
  end
end
