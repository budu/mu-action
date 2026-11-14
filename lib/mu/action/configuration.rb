# frozen_string_literal: true

module Mu
  module Action
    # Global settings, available as Mu::Action.on_undeclared_failure and so on.
    module Configuration
      # How an action handles a failure that its declarations don't allow:
      # +:raise+ (the default) raises an ArgumentError, while a callable is
      # called with the action, the error code and the details.
      attr_reader :on_undeclared_failure

      def on_undeclared_failure=(handler)
        unless handler == :raise || handler.respond_to?(:call)
          raise ArgumentError, "on_undeclared_failure must be :raise or respond to #call"
        end

        @on_undeclared_failure = handler
      end
    end
  end
end
