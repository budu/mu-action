# frozen_string_literal: true

require "mu/action"

RSpec.configure do |config|
  # A focused example narrows a local run. On CI it is ignored, so that one
  # left behind cannot hide the rest of the suite.
  config.filter_run_when_matching :focus unless ENV["CI"]

  # A random order reveals examples that depend on one another.
  config.order = :random
  Kernel.srand config.seed

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
