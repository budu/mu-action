# frozen_string_literal: true

require "literal"

require_relative "action/version"
require_relative "action/configuration"
require_relative "action/failure_error"
require_relative "action/result"
require_relative "action/hooks"
require_relative "action/failures"

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
        include Hooks
        include Failures
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

    # Internal module that passes the props recording of an action class on
    # to its subclasses.
    module HookPropagator
      def inherited(subclass)
        super
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
