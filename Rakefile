# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Run all checks (RuboCop, RSpec, Steep, README examples)"
task default: :check

task :check do
  exec "bin/check"
end
