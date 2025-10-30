# frozen_string_literal: true

require "guard/plugin"

# steep:ignore:start
module Guard
  # Guard plugin that runs Steep type checking whenever files change.
  class Steep < Plugin
    def initialize(options = {})
      super
      @command = options.fetch(:command, "bundle exec steep check")
    end

    def start = run_steep
    def run_all = run_steep
    def run_on_additions(_paths) = run_steep
    def run_on_modifications(_paths) = run_steep
    def run_on_removals(_paths) = run_steep

    private

    def run_steep
      UI.info "📐 Running Steep..."
      success = system(@command)
      UI.error "Steep check failed" unless success
    end
  end
end
# steep:ignore:end
