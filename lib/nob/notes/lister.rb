module Nob
  module Notes
    class Lister
      class InvalidPrefix < Nob::Error; end
      class PrefixNotFound < Nob::Error; end

      def self.list(vault:, prefix: nil)
        normalized_prefix = normalize_prefix(prefix, vault: vault)
        base = normalized_prefix ? File.join(vault, normalized_prefix) : vault

        validate_base!(base, normalized_prefix)

        relatives = Dir.glob("**/*.md", base: base).sort
        relatives.map do |rel|
          rel_from_vault = normalized_prefix ? File.join(normalized_prefix, rel) : rel
          Nob::Entities::Note.new(
            absolute_path: File.join(vault, rel_from_vault),
            relative_path: rel_from_vault
          )
        end
      end

      def self.normalize_prefix(prefix, vault:)
        return nil if prefix.nil? || prefix.empty?

        if File.absolute_path?(prefix)
          raise InvalidPrefix, "prefix must be relative to the vault: #{prefix}"
        end

        stripped = prefix.chomp("/")

        vault_real = File.realpath(vault)
        candidate = File.expand_path(stripped, vault_real)
        unless candidate == vault_real || candidate.start_with?("#{vault_real}#{File::SEPARATOR}")
          raise InvalidPrefix, "prefix escapes the vault: #{prefix}"
        end

        stripped
      end

      def self.validate_base!(base, normalized_prefix)
        return if normalized_prefix.nil?

        unless File.exist?(base)
          raise PrefixNotFound, "prefix directory not found: #{normalized_prefix}"
        end
        unless File.directory?(base)
          raise InvalidPrefix, "prefix must be a directory: #{normalized_prefix}"
        end
      end

      private_class_method :normalize_prefix, :validate_base!
    end
  end
end
