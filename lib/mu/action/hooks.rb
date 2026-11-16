# frozen_string_literal: true

module Mu
  module Action
    # The before, after and around hooks of an action: their registration on
    # the class and their execution around the call.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Hooks
      # The instance variable of an action class that holds the hooks it
      # registers itself, by kind.
      STORE = :@mu_action_hooks

      def self.install(base)
        base.extend(ClassMethods)
      end

      # Runs the hooks of an action around the block, which makes the call:
      # the before hooks, the around hooks wrapped around the block, then the
      # after hooks. Hooks run in the action, with instance_exec or send.
      def self.run(action, &)
        of(action.class, :before).each { run_hook(action, _1) }
        # An around hook can replace the result, so what the chain returns is
        # checked like what the call returns.
        result = Action.own_result(action, around_chain(action, &).call, "an around hook")
        of(action.class, :after).each { run_hook(action, _1) }
        result
      end

      # The hooks of one kind of an action class: those of its parent class,
      # followed by its own. They are worked out when read, so that a hook added
      # to a parent class reaches its subclasses whenever it is added.
      def self.of(action_class, kind)
        parent = Action.parent(action_class)
        inherited = parent ? of(parent, kind) : [] #: ::Array[untyped]
        inherited + own(action_class, kind)
      end

      # Registers hooks of one kind on an action class: a block, or the names
      # of methods of the action.
      def self.register(action_class, kind, method_names, block)
        hooks = block ? [checked_block(kind, method_names, block)] : hook_names(kind, method_names)
        store = action_class.instance_variable_get(STORE) || {}
        action_class.instance_variable_set(STORE, store.merge(kind => [*store[kind], *hooks]))
        nil
      end

      # How many positional arguments a hook takes, from its parameters. A hook
      # that takes any number of them counts as taking two.
      def self.positional_arity(parameters)
        return 2 if parameters.any? { |type, _| type == :rest }

        parameters.count { |type, _| %i[req opt].include?(type) }
      end

      # Class methods that register hooks and list them.
      #
      # @api public
      module ClassMethods
        def before(*method_names, &block) = Hooks.register(self, :before, method_names, block)
        def after(*method_names, &block) = Hooks.register(self, :after, method_names, block)

        # An around hook takes the chain, or the action and the chain, and calls
        # the chain to continue. A method can also take nothing and yield.
        def around(*method_names, &block) = Hooks.register(self, :around, method_names, block)

        # The hooks of the class, those of its parent class first. Each one is
        # a block or the name of a method. They are for inspection: changing
        # what these methods return does not change the hooks that run.
        def before_hooks = Hooks.of(self, :before)
        def after_hooks = Hooks.of(self, :after)
        def around_hooks = Hooks.of(self, :around)
      end

      class << self
        private

        def own(action_class, kind)
          action_class.instance_variable_get(STORE)&.fetch(kind, nil) || []
        end

        def checked_block(kind, method_names, block)
          raise ArgumentError, "#{kind} hooks accept either a block or method names, not both" if method_names.any?
          if kind == :around && positional_arity(block.parameters).zero?
            raise ArgumentError, "an around block takes the chain, or the action and the chain"
          end

          block
        end

        def hook_names(kind, method_names)
          raise ArgumentError, "#{kind} hook requires a block or method name" if method_names.empty?

          method_names.map do |name|
            raise ArgumentError, "Invalid #{kind} hook identifier: #{name.inspect}" unless name.respond_to?(:to_sym)

            name.to_sym
          end
        end

        def run_hook(action, hook)
          if hook.is_a?(Proc)
            # @type var hook: ^(*untyped) -> untyped
            return action.instance_exec(&hook)
          end

          action.send(hook)
        end

        def around_chain(action, &block)
          chain = block
          of(action.class, :around).reverse_each do |hook|
            previous = chain
            chain = around_link(action, hook, previous)
          end
          chain
        end

        def around_link(action, hook, previous)
          case hook
          when Proc
            arguments = around_arguments(action, hook.parameters, previous)
            lambda do
              # @type var hook: ^(*untyped) -> untyped
              action.instance_exec(*arguments, &hook)
            end
          else
            -> { call_around_method(action, hook, previous) }
          end
        end

        def call_around_method(action, hook, previous)
          method_object = around_method(action, hook.to_sym)
          arguments = around_arguments(action, method_object.parameters, previous)
          method_object.bind(action).call(*arguments, &previous)
        end

        # The arguments of an around hook, a block or a method: the chain when
        # it takes one, the action and the chain when it takes two.
        def around_arguments(action, parameters, previous)
          case positional_arity(parameters)
          when 0 then []
          when 1 then [previous]
          else [action, previous]
          end
        end

        def around_method(action, method_name)
          action.class.instance_method(method_name)
        rescue NameError
          raise NoMethodError, "Undefined hook method ##{method_name} for #{action.class}"
        end
      end
    end
  end
end
