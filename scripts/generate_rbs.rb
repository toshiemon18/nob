#!/usr/bin/ruby

require "fileutils"
require "open3"

lib_dir = Pathname.new("./") + "lib"

Dir.glob(File.join(lib_dir.to_s, "**", "*.rb")).each do |entry|
  entry_path = entry.to_s
  signature_path = Pathname.new("./sig") + entry_path.split("/")[1..].join("/")
  base_dir = signature_path.to_s.split("/")[0..-2].join("/")
  FileUtils.mkdir_p(base_dir) unless Dir.exist?(base_dir)

  cmd = "bundle exec typeprof -o #{signature_path}s #{entry}"
  Open3.popen3(cmd) do |stdin, stdout, stderr, wait_thr|
    err = stderr.read
    unless err.empty?
      puts err
    end
  end
  # puts cmd
end
