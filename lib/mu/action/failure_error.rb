# frozen_string_literal: true

module Mu
  module Action
    # Exception class for action failures. Carries the error code and its
    # details. When raised by +call!+, it also carries the Failure result.
    class FailureError < StandardError
      attr_reader :error, :details, :failure

      def initialize(error, details: {}, failure: nil)
        @error = error
        @details = details
        @failure = failure
        super(error)
      end
    end
  end
end
