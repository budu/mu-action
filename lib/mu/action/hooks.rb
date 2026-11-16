# frozen_string_literal: true

module Mu
  module Action
    # The before, after and around hooks of an action: their registration on
    # the class and their execution around the call.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Hooks
      def self.install(base)
        base.extend(ClassMethods)
      end

      # Runs the hooks of an action around the block, which makes the call:
      # the before hooks, the around hooks wrapped around the block, then the
      # after hooks. Hooks run in the action, with instance_exec or send.
      def self.run(action, &)
        action.class.before_hooks.each { run_hook(action, _1) }
        # An around hook can replace the result, so what the chain returns is
        # checked like what the call returns.
        result = Action.own_result(action, around_chain(action, &).call, "an around hook")
        action.class.after_hooks.each { run_hook(action, _1) }
        result
      end

      # How many positional arguments a hook takes, from its parameters. A hook
      # that takes any number of them counts as taking two.
      def self.positional_arity(parameters)
        return 2 if parameters.any? { |type, _| type == :rest }

        parameters.count { |type, _| %i[req opt].include?(type) }
      end

      # Class methods that register hooks, as blocks or as method names.
      #
      # A class keeps the hooks it registers itself. The hooks of an action are
      # those of its parent class followed by its own, worked out when they are
      # read, so that a hook added to a parent reaches its subclasses whenever
      # it is added.
      #
      # @api public
      module ClassMethods
        # An around hook takes the chain, or the action and the chain, and calls
        # the chain to continue. A method can also take nothing and yield.
        def around(*method_names, &block)
          if block && Hooks.positional_arity(block.parameters).zero?
            raise ArgumentError, "an around block takes the chain, or the action and the chain"
          end

          register_hook(method_names, block, name: :around)
        end

        def before(*method_names, &block) = register_hook(method_names, block, name: :before)
        def after(*method_names, &block) = register_hook(method_names, block, name: :after)

        def around_hooks = parent_hooks(:around_hooks) + own_hooks(:around)
        def before_hooks = parent_hooks(:before_hooks) + own_hooks(:before)
        def after_hooks = parent_hooks(:after_hooks) + own_hooks(:after)

        private

        def own_hooks(name) = @own_hooks&.fetch(name, nil) || []

        def parent_hooks(reader)
          # @type var parent: untyped
          parent = superclass
          parent.respond_to?(reader) ? parent.public_send(reader) : []
        end

        def register_hook(method_names, block, name:)
          ensure_valid_hook_inputs(method_names, block, name:)
          additions = normalize_hook_inputs(method_names, block, name:)
          hooks = (@own_hooks ||= {}) #: ::Hash[Symbol, ::Array[untyped]]
          (hooks[name] ||= []).concat(additions)
        end

        def normalize_hook_inputs(method_names, block, name:)
          if block
            [block]
          else
            symbolize_hook_names(method_names, name:)
          end
        end

        def ensure_valid_hook_inputs(method_names, block, name:)
          return unless block && method_names.any?

          raise ArgumentError, "#{name} hooks accept either a block or method names, not both"
        end

        def symbolize_hook_names(method_names, name:)
          raise ArgumentError, "#{name} hook requires a block or method name" if method_names.empty?

          method_names.map do |method_name|
            unless method_name.respond_to?(:to_sym)
              raise ArgumentError, "Invalid #{name} hook identifier: #{method_name.inspect}"
            end

            method_name.to_sym
          end
        end
      end

      class << self
        private

        def run_hook(action, hook)
          if hook.is_a?(Proc)
            # @type var hook: ^(*untyped) -> untyped
            return action.instance_exec(&hook)
          end

          action.send(hook)
        end

        def around_chain(action, &block)
          chain = block
          action.class.around_hooks.reverse_each do |hook|
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
