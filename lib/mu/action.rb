# frozen_string_literal: true

require "literal"

require_relative "action/version"
require_relative "action/configuration"
require_relative "action/failure_error"
require_relative "action/result"

module Mu
  # Provides an interactor pattern implementation with hooks, metadata tracking,
  # and result wrapping.
  module Action
    extend Configuration

    self.on_undeclared_failure = :raise

    # Fiber storage key holding the context of the running action, inherited
    # by the actions it calls.
    CONTEXT_KEY = :mu_action_context

    def self.included(base)
      base.class_eval do
        extend Literal::Properties
        extend ClassMethods
        include Initializer
        include FailureChecking
        singleton_class.prepend(MetaPropAdder)
        singleton_class.prepend(HookPropagator)

        attr_reader :meta, :context
      end
    end

    # Internal module that automatically adds the meta and context properties
    # to action classes when they are instantiated. Ensures proper metadata
    # initialization.
    module MetaPropAdder
      def new(...)
        unless @meta_prop_added
          prop :meta, Hash, default: -> { {} } # steep:ignore UnannotatedEmptyCollection
          prop :context, _Nilable(_Any), default: -> { Fiber[CONTEXT_KEY] }
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

    # Internal module that ensures hook arrays and failure declarations are
    # properly duplicated when action classes are inherited, preventing shared
    # state between classes.
    module HookPropagator
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@before_hooks, before_hooks.dup)
        subclass.instance_variable_set(:@after_hooks, after_hooks.dup)
        subclass.instance_variable_set(:@around_hooks, around_hooks.dup)
        subclass.instance_variable_set(:@own_failures, own_failures.dup)
        subclass.instance_variable_set(:@failure_sources, failure_sources.dup)
        subclass.instance_variable_set(:@props_recording, props_recording)
      end
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
        @meta = meta.dup
        meta[:class] = self.class
        props = recorded_props
        meta[:props] = props if props
        meta[:context] = context unless context.nil?
      end

      def recorded_props
        recording = self.class.props_recording
        return if recording == false

        props = self.class.literal_properties.to_h do |prop|
          [prop.name, instance_variable_get(:"@#{prop.name}")] #: [Symbol, untyped]
        end.except(:meta, :context)

        case recording
        in { only: } then props.slice(*only)
        in { except: } then props.except(*except)
        else props
        end
      end
    end

    # Internal module that builds Failure results and checks failures against
    # the action's declarations.
    module FailureChecking
      private

      def failure_from(exception)
        cause = exception.failure
        check_failure(exception.error, exception.details, origin: cause.meta[:class]) if cause
        # @type var failure_meta: ::Hash[Symbol, untyped]
        failure_meta = { **meta, failure_error: exception }
        failure_meta[:cause] = cause if cause
        Failure.new(exception.error, details: exception.details, meta: failure_meta)
      end

      def check_failure(error, details, origin: nil)
        return unless self.class.declares_failures?
        return if origin && self.class.failure_sources.any? { origin <= _1 }

        problem = failure_problem(error, details)
        return unless problem

        case (handler = Mu::Action.on_undeclared_failure)
        when :raise then raise ArgumentError, "#{self.class}: #{problem}"
        else handler.call(self, error, details)
        end
      end

      def failure_problem(error, details)
        failures = self.class.failures
        return "undeclared failure #{error.inspect}" unless failures.key?(error)

        types = failures[error]
        unexpected = details.keys - types.keys
        return "unexpected details #{unexpected.inspect} for failure #{error.inspect}" if unexpected.any?

        detail_problem(error, types, details)
      end

      def detail_problem(error, types, details)
        types.each do |key, type|
          value = details[key]
          next if type === value # rubocop:disable Style/CaseEquality

          return "detail #{key.inspect} of failure #{error.inspect} must be #{type.inspect}, got #{value.inspect}"
        end
        nil
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
        result = new(...).run
        case result
        in Success(value:)
          value
        in Failure(error:, details:, meta:)
          raise FailureError.new(error, details:, failure: result), cause: meta[:failure_error]
        else
          result
        end
      end

      # Chooses which props are recorded in meta[:props]: all of them (the
      # default), none, or a subset.
      #
      #   record_props false
      #   record_props only: %i[site_id]
      #   record_props except: %i[payload]
      def record_props(enabled = true, only: nil, except: nil) # rubocop:disable Style/OptionalBooleanParameter
        @props_recording = build_props_recording(enabled, only, except)
      end

      def props_recording = (defined?(@props_recording) ? @props_recording : true)

      # Declares the failures this action can return. Once an action declares
      # any, other failures are handled by Mu::Action.on_undeclared_failure.
      #
      #   failure :site_disabled
      #   failure :invalid, errors: ActiveModel::Errors
      #   failure from: OtherAction
      def failure(*codes, from: nil, **details)
        raise ArgumentError, "failure requires a code or from:" if codes.empty? && !from
        raise ArgumentError, "details can only be declared for a single failure" if codes.size > 1 && details.any?

        codes.each { own_failures[_1] = details }
        failure_sources.concat(Array(from))
      end

      # The declared failures, including those of the +from:+ actions,
      # as a hash of error code to details types.
      def failures
        failure_sources.map(&:failures).reduce({}, :merge).merge(own_failures)
      end

      def declares_failures? = own_failures.any? || failure_sources.any?
      def own_failures = (@own_failures ||= {})
      def failure_sources = (@failure_sources ||= [])

      def result(type)
        success_class = Class.new(::Mu::Action::Success) do
          # @type self: singleton(::Mu::Action::Success)
          prop :value, type, :positional
        end

        const_set(:Success, success_class)
      end

      private

      def build_props_recording(enabled, only, except)
        raise ArgumentError, "record_props accepts only: or except:, not both" if only && except

        # @type var filter: ::Hash[Symbol, ::Array[Symbol]]
        filter = { only:, except: }.compact.transform_values { Array(_1) }
        return filter.empty? || filter if enabled
        raise ArgumentError, "record_props false accepts no only: or except:" if filter.any?

        false
      end

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
    def Success(value = nil) = self.class.const_get(:Success).new(value, meta:)

    def Failure(error, **details)
      check_failure(error, details)
      raise FailureError.new(error, details:)
    end
    # rubocop:enable Naming/MethodName

    def run
      run!
    rescue FailureError => e
      failure_from(e)
    end

    def run!
      with_context { with_hooks { call } }
    end

    protected

    def with_context
      previous = Fiber[CONTEXT_KEY]
      Fiber[CONTEXT_KEY] = context
      yield
    ensure
      Fiber[CONTEXT_KEY] = previous
    end

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
