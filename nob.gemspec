require_relative "lib/nob/version"

Gem::Specification.new do |spec|
  spec.name = "nob"
  spec.version = Nob::VERSION
  spec.authors = ["Toshiaki Seino"]
  spec.email = ["st12318@gmail.com"]

  spec.summary = "Obsidian-like note manager for CLI and Neovim"
  spec.description = "A minimal CLI toolchain to manage Markdown notes, daily notes and wiki-style links over an existing Obsidian vault."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE.txt"].select { |f| File.file?(f) }
  spec.bindir = "exe"
  spec.executables = ["nob"]
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "toml-rb", "~> 4.0"
  spec.add_dependency "front_matter_parser", "~> 1.0"
end
