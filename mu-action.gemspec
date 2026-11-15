# frozen_string_literal: true

require_relative "lib/mu/action/version"

Gem::Specification.new do |spec|
  spec.name = "mu-action"
  spec.version = Mu::Action::VERSION
  spec.authors = ["Nicolas Buduroi"]
  spec.email = ["nbuduroi@gmail.com"]

  spec.summary = "Modern interactor pattern with type safety and metadata tracking"
  spec.description = "A Ruby gem providing interactor pattern implementation with enhanced type safety, " \
                     "metadata tracking, and hook system built on Literal gem"
  spec.homepage = "https://github.com/budu/mu-action"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["source_code_uri"] = "https://github.com/budu/mu-action"
  spec.metadata["changelog_uri"] = "https://github.com/budu/mu-action/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Only the library, its RBS signatures and the docs are released. sig/kernel.rbs and
  # sig/literal.rbs are local stubs for Steep.
  docs = %w[README.md LICENSE.txt CHANGELOG.md]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |f|
      f.start_with?("lib/mu/", "sig/mu/") || docs.include?(f)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "literal", "~> 1.9"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
