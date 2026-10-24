require "tmpdir"
require "fileutils"

# Helpers for tests that need a fresh, writable vault.
#
# Usage in a spec:
#
#   include_context "tmp vault"
#
# Each example gets an empty vault at @vault and a config.toml at
# @config_path pointing at it; Config.default_path is stubbed to return
# @config_path. Call write_config(toml) to replace the config contents.
RSpec.shared_context("tmp vault") do
  before do
    @vault = Dir.mktmpdir("nob-vault")
    @_tmp_cfg_dir = Dir.mktmpdir("nob-cfg")
    @config_path = File.join(@_tmp_cfg_dir, "nob", "config.toml")
    FileUtils.mkdir_p(File.dirname(@config_path))
    write_config("vault = \"#{@vault}\"\n")
    allow(Nob::Config).to(receive(:default_path).and_return(@config_path))
  end

  after do
    FileUtils.remove_entry(@vault) if @vault
    FileUtils.remove_entry(@_tmp_cfg_dir) if @_tmp_cfg_dir
  end

  def write_config(toml)
    File.write(@config_path, toml)
  end
end
