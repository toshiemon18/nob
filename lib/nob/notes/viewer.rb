require "front_matter_parser"
require "date"

module Nob
  module Notes
    class Viewer
      class NotFound < Nob::Error; end
      class Ambiguous < Nob::Error; end
      class InvalidFrontmatter < Nob::Error; end

      # Creator は Date を frontmatter に書き出すため、loader 側で Date/Time を許可しておく
      YAML_LOADER = FrontMatterParser::Loader::Yaml.new(
        allowlist_classes: [Date, Time]
      )

      def self.show(vault:, title:)
        relatives = Dir.glob("**/*.md", base: vault)
        matches = relatives.select { |rel| File.basename(rel, ".md") == title }

        if matches.empty?
          raise NotFound, "note not found: #{title}"
        end

        if matches.size > 1
          sorted = matches.sort_by { |m| [File.basename(m), m] }
          raise Ambiguous, %(multiple notes match "#{title}": #{sorted.join(", ")})
        end

        rel = matches.first
        abs = File.join(vault, rel)

        parsed = begin
          FrontMatterParser::Parser.parse_file(abs, loader: YAML_LOADER)
        rescue Psych::SyntaxError => e
          raise InvalidFrontmatter, "invalid YAML frontmatter in #{rel}: #{e.message}"
        end
        frontmatter = parsed.front_matter || {}
        content = parsed.content

        note = Nob::Entities::Note.new(absolute_path: abs, relative_path: rel)
        Nob::Entities::NoteDetail.new(
          note: note,
          size: File.size(abs),
          chars: content.length,
          frontmatter: frontmatter
        )
      end
    end
  end
end
