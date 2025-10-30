# frozen_string_literal: true

require_relative "action/version"
require "literal"

module Mu
  # Provides an interactor pattern implementation with hooks, metadata tracking,
  # and result wrapping.
  module Action
    def self.included(base)
      base.class_eval do
        extend Literal::Properties
        extend ClassMethods
        include Initializer
        singleton_class.prepend(MetaPropAdder)
        singleton_class.prepend(HookPropagator)

        attr_reader :meta
      end
    end

    # Internal module that automatically adds a meta property to action classes
    # when they are instantiated. Ensures proper metadata initialization.
    module MetaPropAdder
      def new(...)
        unless @meta_prop_added
          prop :meta, Hash, default: -> { {} } # steep:ignore UnannotatedEmptyCollection
          @meta_prop_added = true
        end
        instance = super
        # Ensure meta is initialized for this specific class
        instance.send(:initialize_meta) if instance.respond_to?(:initialize_meta, true)
        instance
      end

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@meta_prop_added, false)
      end
    end

    # Internal module that ensures hook arrays are properly duplicated when
    # action classes are inherited, preventing shared state between classes.
    module HookPropagator
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
        subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
        subclass.instance_variable_set(:@around_hooks, around_hooks.dup)
      end
    end

    # Exception class for action failures. Wraps the original error
    # and includes metadata for debugging and logging purposes.
    class FailureError < StandardError
      attr_reader :error, :meta

      def initialize(error, meta: {})
        @error = error
        @meta = meta
        super(error)
      end
    end

    # Base result class that wraps action outcomes with success/failure state
    # and metadata. Extended by Success and Failure classes for pattern matching.
    class Result < Literal::Struct
      prop :meta, Hash, default: -> { {} } # steep:ignore UnannotatedEmptyCollection

      attr_reader :meta
    end

    # Success result class for pattern matching
    class Success < Result
      prop :value, _Any, :positional, default: nil

      attr_reader :value

      def success? = true
      def failure? = false
    end

    # Failure result class for pattern matching
    class Failure < Result
      prop :error, _Any, :positional, default: nil

      attr_reader :error

      def success? = false
      def failure? = true
    end

    # Internal module that handles action initialization, automatically
    # tracking class information and property values in metadata.
    module Initializer
      def initialize(...)
        super
        initialize_meta
      end

      private

      def initialize_meta
        meta[:class] = self.class
        meta[:props] = self.class.literal_properties.to_h do |prop|
          [prop.name, instance_variable_get(:"@#{prop.name}")]
        end.except(:meta)
      end
    end

    # Class methods added to action classes when including Mu::Action.
    # Provides hook registration, execution methods, and result type definition.
    module ClassMethods
      def around(*method_names, &block) = register_hook(around_hooks, method_names, block, name: :around)
      def before(*method_names, &block) = register_hook(before_hooks, method_names, block, name: :before)
      def after(*method_names, &block) = register_hook(after_hooks, method_names, block, name: :after)

      def around_hooks = (@around_hooks ||= [])
      def before_hooks = (@before_hooks ||= [])
      def after_hooks = (@after_hooks ||= [])

      def call(...) = new(...).run

      def call!(...)
        result = new(...).run!
        case result
        in Success(value:)
          value
        in Failure(meta: { failure_error: })
          raise failure_error
        else
          result
        end
      end

      def result(type)
        success_class = Class.new(::Mu::Action::Success) do
          prop :value, type, :positional, default: nil
        end

        const_set(:Success, success_class)
      end

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

    # rubocop:disable Naming/MethodName
    def Success(value) = self.class.const_get(:Success).new(value, meta:)
    def Failure(error, **meta) = raise FailureError.new(error, meta:)
    # rubocop:enable Naming/MethodName

    def run
      run!
    rescue FailureError => e
      Failure.new(e.error, meta: { failure_error: e, **meta, **e.meta })
    end

    def run!
      with_hooks { call }
    end

    protected

    def result_class = self.class.const_get(:Result)

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

    def call
      raise NotImplementedError, "You must implement the call method"
    end
  end
end
