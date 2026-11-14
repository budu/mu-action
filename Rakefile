# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Run all checks (RuboCop, RSpec, Steep, README examples) on the current Ruby"
task :ci do
  exec "bin/ci", "--current"
end

task default: :ci
