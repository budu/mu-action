# frozen_string_literal: true

require "literal"

require_relative "action/version"
require_relative "action/failure_error"
require_relative "action/result"
require_relative "action/context"
require_relative "action/metadata"
require_relative "action/hooks"
require_relative "action/failures"

module Mu
  # Provides an interactor pattern implementation with hooks, metadata tracking,
  # and result wrapping.
  #
  # An action class resolves the constants defined here by their bare name,
  # ahead of the application's top-level constants, so each constant added
  # under Mu::Action is a name applications can no longer use unqualified.
  module Action
    class << self
      # How an action handles a failure that its declarations don't allow:
      # +:raise+ (the default) raises an ArgumentError, while a callable is
      # called with the action, the error code and the details.
      attr_reader :on_undeclared_failure

      def on_undeclared_failure=(handler)
        unless handler == :raise || handler.respond_to?(:call)
          raise ArgumentError, "on_undeclared_failure must be :raise or respond to #call"
        end

        @on_undeclared_failure = handler
      end
    end

    self.on_undeclared_failure = :raise

    def self.included(base)
      # Ruby calls this hook each time, so including Mu::Action again, in the
      # same class or in a subclass, must change nothing.
      return if base.singleton_class.include?(ClassMethods)

      base.extend(Literal::Properties)
      base.extend(ClassMethods)
      # Metadata and Context declare the meta and context props here, before
      # the props of the action itself.
      [Metadata, Context, Hooks, Failures].each { _1.install(base) }
    end

    # The parent class of an action class, when it is an action class too. What
    # a class declares is combined with what its parent declares through it.
    #
    # @api private
    def self.parent(action_class)
      parent = action_class.superclass
      parent if parent&.include?(self)
    end

    # The Success an action built, which is what its call and its around hooks
    # must return. A Failure can only be returned by another action: it is
    # raised as the FailureError of a call! would be, so that it reaches the
    # around hooks as an exception and becomes the failure of this action.
    #
    # @api private
    def self.own_result(action, value, source)
      return value if value.is_a?(Success) && value.meta.equal?(action.meta)
      raise FailureError.new(value.error, details: value.details, failure: value) if value.is_a?(Failure)

      problem =
        if value.is_a?(Success)
          "the result of another action. Return Success(...) with its value, as in Success(OtherAction.call!(...))"
        else
          "#{value.inspect}. It must return Success(...), or call Failure(...)"
        end
      raise TypeError, "#{action.class}: #{source} returned #{problem}"
    end

    # Class methods added to action classes when including Mu::Action: the
    # entry points and the result type definition.
    module ClassMethods
      # The props that Mu::Action declares itself. An action cannot declare a
      # prop with one of these names.
      RESERVED_PROPS = %i[meta context].freeze

      def prop(name, ...)
        if RESERVED_PROPS.include?(name) && literal_properties.any? { _1.name == name }
          raise ArgumentError, "#{self}: the #{name} prop is reserved by Mu::Action"
        end

        super
      end

      def call(...) = new(...).run

      def call!(...) = new(...).run!.value

      def result(type)
        success_class = Class.new(::Mu::Action::Success) do
          # @type self: singleton(::Mu::Action::Success)
          prop :value, type, :positional
        end

        const_set(:Success, success_class)
      end

      # The type given to result, by the class or by its parent class, or nil
      # when neither declares one. It is read from the Success class of the
      # action, so that it is always the type Success checks.
      def result_type
        success = const_get(:Success)
        success.literal_properties[:value].type unless success.equal?(::Mu::Action::Success)
      end
    end

    # The methods below are all that Mu::Action adds to an action, with the
    # call it implements. An action can override any of them and call super.

    # The metadata of the action, which its result carries. It must be the
    # same Hash on every call: hooks write to it and the result shares it.
    def meta = @meta

    # What the caller says about who is calling and from where.
    def context = @context

    # rubocop:disable Naming/MethodName

    # Builds the result of the action. This is what call must return.
    def Success(value = nil) = self.class.const_get(:Success).new(value, meta:)

    # Fails the action: checks the failure against the declarations, then
    # raises, so that nothing after it runs.
    def Failure(error, **details)
      Failures.check(self, error, details)
      raise FailureError.new(error, details:)
    end
    # rubocop:enable Naming/MethodName

    # Runs the action and returns its result, a Success or a Failure: sets the
    # context, then runs the hooks around the call.
    def run
      Context.with(self) { Hooks.run(self) { Action.own_result(self, call, "call") } }
    rescue FailureError => e
      Failures.result_for(self, e)
    end

    # Runs the action and returns its Success, or raises a FailureError that
    # carries its Failure. An action that calls another one this way takes on
    # its failure, as with the call! of the class.
    def run!
      result = run
      return result unless result.is_a?(Failure)

      raise FailureError.new(result.error, details: result.details, failure: result), cause: result.meta[:failure_error]
    end

    private

    def call
      raise NotImplementedError, "You must implement the call method"
    end

    # Fills in the metadata when the action is built. Override it, and call
    # super, to record something else than the props.
    def initialize_meta
      meta[:class] = self.class
      props = Metadata.recorded_props(self)
      meta[:props] = props if props
      meta[:context] = context unless context.nil?
    end
  end
end
