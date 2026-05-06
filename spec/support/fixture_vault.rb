require "tmpdir"
require "fileutils"

# Helpers for tests that use the pre-built fixture vault under
# spec/fixtures/vault/.  The vault is read-only; config.toml is
# written into a fresh tmpdir so absolute paths stay correct
# regardless of where the repo lives.
#
# Usage in a spec:
#
#   include_context "fixture vault"
#
# This stubs Config.default_path to a tmpdir config pointing at VAULT_PATH
# for the duration of each example in the including context.
module FixtureVault
  # Absolute path to the fixture vault that lives in the repo.
  VAULT_PATH = File.expand_path("../fixtures/vault", __dir__)

  # Expected notes in the fixture vault, sorted by relative path.
  # Update this list whenever spec/fixtures/vault/ changes.
  EXPECTED_NOTES = %w[
    README.md
    daily/2026-04-30.md
    projects/Plan.md
  ].freeze
end

RSpec.shared_context("fixture vault") do
  before do
    @_fixture_cfg_dir = Dir.mktmpdir("nob-cfg")
    config_path = File.join(@_fixture_cfg_dir, "nob", "config.toml")
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, "vault = \"#{FixtureVault::VAULT_PATH}\"\n")
    allow(Nob::Config).to(receive(:default_path).and_return(config_path))
  end

  after do
    FileUtils.remove_entry(@_fixture_cfg_dir) if @_fixture_cfg_dir
    @_fixture_cfg_dir = nil
  end
end
