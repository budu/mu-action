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
          prop :meta, Hash, default: -> { {} }
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
      prop :meta, Hash, default: -> { {} }

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
      def around(&block) = around_hooks << block
      def before(&block) = before_hooks << block
      def after(&block) = after_hooks << block

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

    def run_before_hooks = self.class.before_hooks.each { instance_exec(&_1) }
    def run_after_hooks = self.class.after_hooks.each { instance_exec(&_1) }

    def build_around_chain(&block)
      chain = block
      self.class.around_hooks.reverse_each do |hook|
        previous = chain
        chain = -> { instance_exec(self, previous, &hook) }
      end
      chain
    end

    def call
      raise NotImplementedError, "You must implement the call method"
    end
  end
end
