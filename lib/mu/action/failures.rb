# frozen_string_literal: true

module Mu
  module Action
    # The failures of an action: their declaration on the class, the check of
    # each failure against the declarations, and the Failure result built
    # from a FailureError.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Failures
      # The instance variables of an action class that hold the failures it
      # declares itself, and the actions it names with from:.
      DECLARED = :@mu_action_failures
      SOURCES = :@mu_action_failure_sources

      def self.install(base)
        base.extend(ClassMethods)
      end

      # The Failure result of an action, from the FailureError that stopped it.
      # When the error comes from a call!, the failure of that other action is
      # checked against the declarations and kept as the cause.
      def self.result_for(action, exception)
        cause = exception.failure
        check(action, exception.error, exception.details, origin: cause.meta[:class]) if cause
        # @type var failure_meta: ::Hash[Symbol, untyped]
        failure_meta = { **action.meta, failure_error: exception }
        failure_meta[:cause] = cause if cause
        Failure.new(exception.error, details: exception.details, meta: failure_meta)
      end

      # Checks a failure against what the action declares, and hands one that is
      # not allowed to Mu::Action.on_undeclared_failure.
      def self.check(action, error, details, origin: nil)
        return unless declared?(action.class)
        return if origin && sources(action.class).any? { origin <= _1 }

        problem = problem(of(action.class), error, details)
        return unless problem

        case (handler = Mu::Action.on_undeclared_failure)
        when :raise then raise ArgumentError, "#{action.class}: #{problem}"
        else handler.call(action, error, details)
        end
      end

      # Declares failures on an action class. With codes, every keyword is a
      # detail, including one named from. Without a code, from: names the
      # actions whose failures the action can also return.
      def self.declare(action_class, codes, details)
        return declare_sources(action_class, **details) if codes.empty?
        raise ArgumentError, "details can only be declared for a single failure" if codes.size > 1 && details.any?

        declared = own(action_class).dup
        codes.each { declared[_1] = details }
        action_class.instance_variable_set(DECLARED, declared)
        nil
      end

      # The failures an action class declares, including those of its parent
      # class and of its from: actions, as a hash of error code to details
      # types. They are worked out when read, so that a declaration added to a
      # parent class reaches its subclasses whenever it is added.
      def self.of(action_class)
        lineage(action_class).map { own(_1) }.reduce({}, :merge)
      end

      # Class methods that declare and list the failures of an action.
      #
      # @api public
      module ClassMethods
        # Declares the failures this action can return. Once an action declares
        # any, other failures are handled by Mu::Action.on_undeclared_failure.
        #
        #   failure :site_disabled
        #   failure :invalid, errors: ActiveModel::Errors
        #   failure from: OtherAction
        #
        # With a code, every keyword is a detail, including one named +from+.
        # Without a code, +from:+ names the actions whose failures this action
        # can also return.
        def failure(*codes, **details) = Failures.declare(self, codes, details)

        # The declared failures, including those of the parent class and of the
        # +from:+ actions, as a hash of error code to details types.
        def failures = Failures.of(self)
      end

      class << self
        private

        def declared?(action_class) = sources(action_class).any? || of(action_class).any?
        def own(action_class) = action_class.instance_variable_get(DECLARED) || {}
        def own_sources(action_class) = action_class.instance_variable_get(SOURCES) || []

        # The from: actions of an action class and of its parent classes.
        def sources(action_class)
          parent = Action.parent(action_class)
          inherited = parent ? sources(parent) : [] #: ::Array[untyped]
          inherited + own_sources(action_class)
        end

        # An action class preceded by its parent class and by the actions it
        # takes failures from, each one once, so that actions that name each
        # other do not recurse forever.
        def lineage(action_class, seen = [])
          return [] if seen.include?(action_class)

          seen << action_class
          ancestors = [Action.parent(action_class), *own_sources(action_class)].compact
          ancestors.flat_map { lineage(_1, seen) } << action_class
        end

        def declare_sources(action_class, from: nil, **unexpected)
          raise ArgumentError, "failure requires a code or from:" if from.nil? || unexpected.any?

          # @type var sources: ::Array[untyped]
          sources = Array(from)
          invalid = sources.reject { _1.is_a?(Class) && _1.include?(Mu::Action) }
          raise ArgumentError, "failure from: expects action classes, got #{invalid.inspect}" if invalid.any?

          action_class.instance_variable_set(SOURCES, own_sources(action_class) + sources)
          nil
        end

        def problem(failures, error, details)
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
    end
  end
end
