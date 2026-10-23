#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "pathname"

lib_dir = Pathname.new("./") + "lib"
failures = []

Dir.glob(File.join(lib_dir.to_s, "**", "*.rb")).each do |entry|
  entry_path = entry.to_s
  signature_path = Pathname.new("./sig") + entry_path.split("/")[1..].join("/")
  base_dir = signature_path.to_s.split("/")[0..-2].join("/")
  FileUtils.mkdir_p(base_dir) unless Dir.exist?(base_dir)

  _stdout, stderr, status = Open3.capture3("bundle", "exec", "typeprof", "-o", "#{signature_path}s", entry)
  puts(stderr) unless stderr.empty?
  failures << entry unless status.success?
end

unless failures.empty?
  warn("typeprof failed for: #{failures.join(", ")}")
  exit(1)
end
