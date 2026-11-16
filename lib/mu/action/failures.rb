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
        return unless action.class.declares_failures?
        return if origin && action.class.failure_sources.any? { origin <= _1 }

        problem = problem(action.class.failures, error, details)
        return unless problem

        case (handler = Mu::Action.on_undeclared_failure)
        when :raise then raise ArgumentError, "#{action.class}: #{problem}"
        else handler.call(action, error, details)
        end
      end

      def self.problem(failures, error, details)
        return "undeclared failure #{error.inspect}" unless failures.key?(error)

        types = failures[error]
        unexpected = details.keys - types.keys
        return "unexpected details #{unexpected.inspect} for failure #{error.inspect}" if unexpected.any?

        detail_problem(error, types, details)
      end

      def self.detail_problem(error, types, details)
        types.each do |key, type|
          value = details[key]
          next if type === value # rubocop:disable Style/CaseEquality

          return "detail #{key.inspect} of failure #{error.inspect} must be #{type.inspect}, got #{value.inspect}"
        end
        nil
      end

      private_class_method :problem, :detail_problem

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
        def failure(*codes, **details)
          return declare_failure_sources(**details) if codes.empty?
          raise ArgumentError, "details can only be declared for a single failure" if codes.size > 1 && details.any?

          own = (@own_failures ||= {}) #: ::Hash[untyped, ::Hash[Symbol, untyped]]
          codes.each { own[_1] = details }
        end

        # The declared failures, including those of the parent class and of the
        # +from:+ actions, as a hash of error code to details types. They are
        # worked out when read, so that a declaration added to a parent class
        # reaches its subclasses whenever it is added.
        def failures
          failure_lineage.map(&:own_failures).reduce({}, :merge)
        end

        def declares_failures? = failure_sources.any? || failures.any?

        # The failures this class declares itself.
        def own_failures = @own_failures || {}

        # The +from:+ actions of this class and of its parent classes.
        def failure_sources
          # @type var parent: untyped
          parent = superclass
          inherited = parent.respond_to?(:failure_sources) ? parent.failure_sources : [] #: ::Array[untyped]
          inherited + (@failure_sources || [])
        end

        # This action preceded by its parent class and by the actions it takes
        # failures from, each one once, so that actions that name each other do
        # not recurse forever.
        #
        # @api private
        def failure_lineage(seen = [])
          return [] if seen.include?(self)

          seen << self
          # @type var parent: untyped
          parent = superclass
          ancestors = parent.respond_to?(:failure_lineage) ? [parent] : [] #: ::Array[untyped]
          (ancestors + (@failure_sources || [])).flat_map { _1.failure_lineage(seen) } << self
        end

        private

        def declare_failure_sources(from: nil, **unexpected)
          raise ArgumentError, "failure requires a code or from:" if from.nil? || unexpected.any?

          # @type var sources: ::Array[untyped]
          sources = Array(from)
          invalid = sources.reject { _1.is_a?(Class) && _1.include?(Mu::Action) }
          raise ArgumentError, "failure from: expects action classes, got #{invalid.inspect}" if invalid.any?

          own = (@failure_sources ||= []) #: ::Array[untyped]
          own.concat(sources)
        end
      end
    end
  end
end
