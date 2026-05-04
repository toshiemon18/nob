require "zeitwerk"

Zeitwerk::Loader.for_gem.setup

module Nob
  class Error < StandardError; end
end
