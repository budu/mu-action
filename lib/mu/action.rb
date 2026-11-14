# frozen_string_literal: true

require "literal"

require_relative "action/version"
require_relative "action/configuration"
require_relative "action/failure_error"
require_relative "action/result"
require_relative "action/context"
require_relative "action/metadata"
require_relative "action/hooks"
require_relative "action/failures"

module Mu
  # Provides an interactor pattern implementation with hooks, metadata tracking,
  # and result wrapping.
  module Action
    extend Configuration

    self.on_undeclared_failure = :raise

    def self.included(base)
      base.class_eval do
        extend Literal::Properties
        extend ClassMethods
        # Context comes before Metadata, so that the meta prop is declared
        # before the context prop when the class is first instantiated.
        include Context
        include Metadata
        include Hooks
        include Failures
      end
    end

    # Class methods added to action classes when including Mu::Action: the
    # entry points and the result type definition.
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

      def result(type)
        success_class = Class.new(::Mu::Action::Success) do
          # @type self: singleton(::Mu::Action::Success)
          prop :value, type, :positional
        end

        const_set(:Success, success_class)
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

    private

    def call
      raise NotImplementedError, "You must implement the call method"
    end
  end
end
