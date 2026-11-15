# frozen_string_literal: true

module Mu
  module Action
    # The before, after and around hooks of an action: their registration on
    # the class and their execution around the call.
    module Hooks
      def self.included(base)
        base.extend(ClassMethods)
        base.singleton_class.prepend(Inheritance)
      end

      # Class methods that register hooks, as blocks or as method names.
      module ClassMethods
        def around(*method_names, &block) = register_hook(around_hooks, method_names, block, name: :around)
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
        result = call_chain.call
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
          lambda do
            # @type var hook: ^(*untyped) -> untyped
            instance_exec(self, previous, &hook)
          end
        else
          -> { invoke_around_method(hook, previous) }
        end
      end

      def invoke_around_method(hook, previous)
        method_name = hook.to_sym
        method_object = resolve_method(method_name)
        arguments = around_arguments(method_object, previous)
        method_object.bind(self).call(*arguments, &previous)
      end

      def around_arguments(method_object, previous)
        params = method_object.parameters.reject { _1.first == :block }
        return [] if params.empty?
        return [previous] if params.length == 1

        [self, previous]
      end

      def resolve_method(method_name)
        self.class.instance_method(method_name)
      rescue NameError
        raise NoMethodError, "Undefined hook method ##{method_name} for #{self.class}"
      end
    end
  end
end
