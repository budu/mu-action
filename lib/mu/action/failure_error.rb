# frozen_string_literal: true

module Mu
  module Action
    # Exception class for action failures. Carries the error code and its
    # details. When raised by +call!+ or +run!+, it also carries the Failure
    # result, and its message names the action.
    class FailureError < StandardError
      attr_reader :error, :details, :failure

      def initialize(error, details: {}, failure: nil)
        @error = error
        @details = details
        @failure = failure
        super(summary)
      end

      private

      # "CreateUser failed: invalid (details: errors)". The details are named
      # and not shown: their values may not belong in a log.
      def summary
        text = error.to_s
        action = failure&.meta&.[](:class)
        text = "#{action.name} failed: #{text}" if action.is_a?(Module) && action.name
        details.empty? ? text : "#{text} (details: #{details.keys.join(", ")})"
      end
    end
  end
end
