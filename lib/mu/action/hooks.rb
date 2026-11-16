# frozen_string_literal: true

module Mu
  module Action
    # The before, after and around hooks of an action: their registration on
    # the class and their execution around the call.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Hooks
      def self.included(base)
        base.extend(ClassMethods)
        base.singleton_class.prepend(Inheritance)
      end

      # How many positional arguments a hook takes, from its parameters. A hook
      # that takes any number of them counts as taking two.
      def self.positional_arity(parameters)
        return 2 if parameters.any? { |type, _| type == :rest }

        parameters.count { |type, _| %i[req opt].include?(type) }
      end

      # Class methods that register hooks, as blocks or as method names.
      #
      # @api public
      module ClassMethods
        # An around hook takes the chain, or the action and the chain, and calls
        # the chain to continue. A method can also take nothing and yield.
        def around(*method_names, &block)
          if block && Hooks.positional_arity(block.parameters).zero?
            raise ArgumentError, "an around block takes the chain, or the action and the chain"
          end

          register_hook(around_hooks, method_names, block, name: :around)
        end

        def before(*method_names, &block) = register_hook(before_hooks, method_names, block, name: :before)
        def after(*method_names, &block) = register_hook(after_hooks, method_names, block, name: :after)

        def around_hooks = (@around_hooks ||= [])
        def before_hooks = (@before_hooks ||= [])
        def after_hooks = (@after_hooks ||= [])

        private

        def register_hook(collection, method_names, block, name:)
          ensure_valid_hook_inputs(method_names, block, name:)
          additions = normalize_hook_inputs(method_names, block, name:)
          collection.concat(additions)
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

      # Gives each subclass its own copy of the hooks, so that registering a
      # hook on a subclass never modifies its parent.
      module Inheritance
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
          subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
          subclass.instance_variable_set(:@around_hooks, around_hooks.dup)
        end
      end

      protected

      def with_hooks(&)
        run_before_hooks
        call_chain = build_around_chain(&)
        # An around hook can replace the result, so what the chain returns is
        # checked like what the call returns.
        result = own_result(call_chain.call, "an around hook")
        run_after_hooks
        result
      end

      private

      def run_before_hooks = self.class.before_hooks.each { execute_simple_hook(_1) }
      def run_after_hooks = self.class.after_hooks.each { execute_simple_hook(_1) }

      def build_around_chain(&block)
        chain = block
        self.class.around_hooks.reverse_each do |hook|
          previous = chain
          chain = build_around_wrapper(hook, previous)
        end
        chain
      end

      def execute_simple_hook(hook)
        if hook.is_a?(Proc)
          # @type var hook: ^(*untyped) -> untyped
          return instance_exec(&hook)
        end

        send(hook)
      end

      def build_around_wrapper(hook, previous)
        case hook
        when Proc
          arguments = around_arguments(hook.parameters, previous)
          lambda do
            # @type var hook: ^(*untyped) -> untyped
            instance_exec(*arguments, &hook)
          end
        else
          -> { invoke_around_method(hook, previous) }
        end
      end

      def invoke_around_method(hook, previous)
        method_object = resolve_method(hook.to_sym)
        arguments = around_arguments(method_object.parameters, previous)
        method_object.bind(self).call(*arguments, &previous)
      end

      # The arguments of an around hook, a block or a method: the chain when it
      # takes one, the action and the chain when it takes two.
      def around_arguments(parameters, previous)
        case Hooks.positional_arity(parameters)
        when 0 then []
        when 1 then [previous]
        else [self, previous]
        end
      end

      def resolve_method(method_name)
        self.class.instance_method(method_name)
      rescue NameError
        raise NoMethodError, "Undefined hook method ##{method_name} for #{self.class}"
      end
    end
  end
end
