# frozen_string_literal: true

module Mu
  module Action
    # Base result class that wraps action outcomes with success/failure state
    # and metadata. Extended by Success and Failure classes for pattern matching.
    #
    # A result is immutable: it is frozen and has no writer. The hashes it
    # holds are not frozen, as after hooks write to the metadata once the
    # result is built.
    class Result < Literal::Data
      prop :meta, Hash, default: -> { {} } # steep:ignore UnannotatedEmptyCollection

      attr_reader :meta
    end

    # Success result class for pattern matching
    class Success < Result
      prop :value, _Nilable(_Any), :positional

      attr_reader :value

      def success? = true
      def failure? = false
    end

    # Failure result class for pattern matching
    class Failure < Result
      prop :error, _Any, :positional
      prop :details, Hash, default: -> { {} } # steep:ignore UnannotatedEmptyCollection

      attr_reader :error, :details

      def success? = false
      def failure? = true
    end
  end
end
