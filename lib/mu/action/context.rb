# frozen_string_literal: true

module Mu
  module Action
    # Fiber-local key holding the context of the running action.
    CONTEXT_KEY = :mu_action_context

    # The context of an action: what its caller says about who is calling and
    # from where. An action called by another one inherits its context.
    #
    # The context of the running action is kept in a fiber-local variable, so
    # it follows the call stack and nothing else: a thread or a fiber started
    # by an action does not see it. Storage that new threads inherit would
    # give a thread pool worker the context of whichever action happened to
    # start it, for all the work it does later.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Context
      def self.install(base)
        # The context defaults to the one of the action that is running, if any.
        base.prop :context, base._Nilable(base._Any), default: -> { Thread.current[CONTEXT_KEY] }
      end

      # Runs the block with the context of the action as the one that the
      # actions it calls inherit.
      def self.with(action)
        previous = Thread.current[CONTEXT_KEY]
        Thread.current[CONTEXT_KEY] = action.context
        yield
      ensure
        Thread.current[CONTEXT_KEY] = previous
      end
    end
  end
end
