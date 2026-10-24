require "nob"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand(config.seed)

  config.around do |example|
    example.run
  rescue SystemExit => e
    raise "unexpected exit(#{e.status}); wrap the call in expect { ... }.to(raise_error(SystemExit))"
  end
end
