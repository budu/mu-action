# frozen_string_literal: true

require "guard/steep"

guard :rubocop, cli: "--format progress" do
  watch(/.+\.rb$/)
  watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { File.dirname(_1[0]) }
end

guard :steep, command: "bundle exec steep check" do
  watch("Steepfile")
  watch(%r{^sig/.+\.rbs$})
  watch(%r{^lib/.+\.rb$})
end

guard :rspec, cmd: "bundle exec rspec" do
  require "guard/rspec/dsl"
  dsl = Guard::RSpec::Dsl.new(self)

  # Ruby files
  ruby = dsl.ruby
  dsl.watch_spec_files_for(ruby.lib_files)

  # RSpec files
  rspec = dsl.rspec
  watch(rspec.spec_helper) { rspec.spec_dir }
  watch(rspec.spec_support) { rspec.spec_dir }
  watch(rspec.spec_files)

  # Watch lib files
  watch(%r{^lib/(.+)\.rb$}) { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r{^lib/mu/action/(.+)\.rb$}) { "spec/mu/action_spec.rb" }
  watch(%r{^lib/mu/action\.rb$}) { Dir["spec/*"] }
end
