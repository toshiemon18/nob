require "thor"
require_relative "../nob"

module Nob
  class CLI < Thor
    def self.exit_on_failure? = true

    desc "version", "Print nob version"
    def version
      puts Nob::VERSION
    end

    desc "create TITLE", "Create a new note under the vault"
    method_option :dir, aliases: "-d", type: :string, desc: "Subdirectory under vault (e.g. projects, daily/2026)"
    method_option :force, aliases: "-f", type: :boolean, default: false, desc: "Backup existing file and recreate"
    def create(title)
      config = Nob::Config.load
      result = Nob::Note.create(
        title: title,
        vault: config.vault,
        dir: options[:dir],
        force: options[:force]
      )
      puts "Created: #{result.path}"
      puts "Backup : #{result.backup_path}" if result.backup_path
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    desc "list", "List notes under the vault"
    method_option :prefix, type: :string, desc: "Filter by vault-relative subdirectory (e.g. daily, projects/2026)"
    def list
      config = Nob::Config.load
      entries = Nob::NoteList.list(vault: config.vault, prefix: options[:prefix])
      entries.each { |entry| puts entry.relative_path }
    rescue Nob::Error => e
      warn "Error: #{e.message}"
      exit 1
    end
  end
end
