# frozen_string_literal: true

module Mu
  module Action
    # Fiber storage key holding the context of the running action, inherited
    # by the actions it calls.
    CONTEXT_KEY = :mu_action_context

    # The context of an action: what its caller says about who is calling and
    # from where. An action called by another one inherits its context.
    module Context
      def self.included(base)
        # The context defaults to the one of the action that is running, if any.
        base.prop :context, base._Nilable(base._Any), default: -> { Fiber[CONTEXT_KEY] }
        base.attr_reader :context
      end

      protected

      def with_context
        previous = Fiber[CONTEXT_KEY]
        Fiber[CONTEXT_KEY] = context
        yield
      ensure
        Fiber[CONTEXT_KEY] = previous
      end
    end
  end
end
