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
      def self.included(base)
        base.extend(ClassMethods)
        base.singleton_class.prepend(Inheritance)
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
        def failure(*codes, **details)
          return declare_failure_sources(**details) if codes.empty?
          raise ArgumentError, "details can only be declared for a single failure" if codes.size > 1 && details.any?

          codes.each { own_failures[_1] = details }
        end

        # The declared failures, including those of the +from:+ actions,
        # as a hash of error code to details types.
        def failures
          failure_lineage.map(&:own_failures).reduce({}, :merge)
        end

        def declares_failures? = own_failures.any? || failure_sources.any?
        def own_failures = (@own_failures ||= {})
        def failure_sources = (@failure_sources ||= [])

        # This action preceded by the actions it takes failures from, each one
        # once, so that actions that name each other do not recurse forever.
        #
        # @api private
        def failure_lineage(seen = [])
          return [] if seen.include?(self)

          seen << self
          failure_sources.flat_map { _1.failure_lineage(seen) } << self
        end

        private

        def declare_failure_sources(from: nil, **unexpected)
          raise ArgumentError, "failure requires a code or from:" if from.nil? || unexpected.any?

          # @type var sources: ::Array[untyped]
          sources = Array(from)
          invalid = sources.reject { _1.is_a?(Class) && _1.include?(Mu::Action) }
          raise ArgumentError, "failure from: expects action classes, got #{invalid.inspect}" if invalid.any?

          failure_sources.concat(sources)
        end
      end

      # Gives each subclass its own copy of the declarations, so that declaring
      # a failure on a subclass never modifies its parent.
      module Inheritance
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@own_failures, own_failures.dup)
          subclass.instance_variable_set(:@failure_sources, failure_sources.dup)
        end
      end

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
  end
end
