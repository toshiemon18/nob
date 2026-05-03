require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.setup

module Nob
  class Error < StandardError; end
end
