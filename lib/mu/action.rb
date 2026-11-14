# frozen_string_literal: true

require "literal"

require_relative "action/version"
require_relative "action/configuration"
require_relative "action/failure_error"
require_relative "action/result"
require_relative "action/hooks"

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
        include Hooks
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

    # Internal module that ensures failure declarations are properly
    # duplicated when action classes are inherited, preventing shared state
    # between classes.
    module HookPropagator
      def inherited(subclass)
        super
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

    private

    def call
      raise NotImplementedError, "You must implement the call method"
    end
  end
end
