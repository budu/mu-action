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
        base.singleton_class.prepend(Lifecycle)
        base.attr_reader :context
      end

      # Adds the context prop the first time an action class is instantiated.
      # It defaults to the context of the action that is running, if any.
      module Lifecycle
        def new(...)
          unless @context_prop_added
            prop :context, _Nilable(_Any), default: -> { Fiber[CONTEXT_KEY] }
            @context_prop_added = true
          end
          super
        end
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
