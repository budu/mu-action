# frozen_string_literal: true

RSpec.describe Mu::Action::Result do
  describe "#success?" do
    it "returns true when error is nil" do
      result = Mu::Action::Success.new("value")
      expect(result.success?).to be true
    end

    it "returns false when error is present" do
      result = Mu::Action::Failure.new("error")
      expect(result.success?).to be false
    end
  end

  describe "#failure?" do
    it "returns false when error is nil" do
      result = Mu::Action::Success.new("value")
      expect(result.failure?).to be false
    end

    it "returns true when error is present" do
      result = Mu::Action::Failure.new("error")
      expect(result.failure?).to be true
    end
  end

  describe "immutability" do
    let(:success) { Mu::Action::Success.new("value", meta: { source: :spec }) }
    let(:failure) { Mu::Action::Failure.new(:invalid, details: { field: :name }) }

    it "freezes a result" do
      expect(success).to be_frozen
      expect(failure).to be_frozen
    end

    it "has no writer" do
      writers = %i[value= meta= error= details= []=]

      expect(writers.select { success.respond_to?(_1) || failure.respond_to?(_1) }).to be_empty
      expect { success.value = "other" }.to raise_error(NoMethodError)
      expect { failure.error = :other }.to raise_error(NoMethodError)
    end

    it "freezes the result of an action, whatever its result type" do
      typed = Class.new do
        include Mu::Action

        result String

        def call = Success("typed")
      end
      failing = Class.new do
        include Mu::Action

        def call = Failure(:nope)
      end

      expect(typed.call).to be_frozen
      expect(failing.call).to be_frozen
    end

    it "leaves the metadata open, for the after hooks that write to it" do
      hooked = Class.new do
        include Mu::Action

        after { meta[:finished] = true }

        def call = Success(:done)
      end

      expect(hooked.call.meta).to include(finished: true)
    end
  end

  describe "custom result types" do
    let(:action_class) do
      Class.new do
        include Mu::Action

        prop :value, _Any, default: "typed result"
        result String

        def call = Success(@value)
      end
    end

    it "uses custom success class" do
      expect(action_class.call).to be_a(action_class::Success)
    end

    it "raises type error" do
      expect { action_class.call(value: 1) }
        .to raise_error(Literal::TypeError, /Expected: String/)
    end

    it "rejects nil unless the type allows it" do
      action_class.define_method(:call) { Success() }

      expect { action_class.call }.to raise_error(Literal::TypeError)
    end

    it "accepts nil when the type allows it" do
      nilable = Class.new do
        include Mu::Action

        result _Nilable(String)

        def call = Success()
      end

      expect(nilable.call!).to be_nil
    end
  end

  describe "nil values" do
    let(:action_class) do
      Class.new do
        include Mu::Action

        prop :empty, _Boolean, default: false

        def call = @empty ? Success() : Success(nil)
      end
    end

    it "accepts nil as the value of an untyped action" do
      expect(action_class.call.value).to be_nil
      expect(action_class.call!).to be_nil
    end

    it "defaults the value to nil when Success is called without one" do
      expect(action_class.call(empty: true).value).to be_nil
    end

    it "builds a Success without a value" do
      expect(Mu::Action::Success.new.value).to be_nil
    end

    it "requires an error for a Failure" do
      expect { Mu::Action::Failure.new }.to raise_error(ArgumentError)
      expect { Mu::Action::Failure.new(nil) }.to raise_error(Literal::TypeError)
    end
  end

  describe "pattern matching" do
    it "matches Success results" do
      result = Mu::Action::Success.new("test value")
      matched = case result
                in Mu::Action::Success
                  "success"
                else
                  "other"
                end

      expect(matched).to eq("success")
    end

    it "matches Failure results" do
      result = Mu::Action::Failure.new("test error")
      matched = case result
                in Mu::Action::Failure
                  "failure"
                else
                  "other"
                end

      expect(matched).to eq("failure")
    end

    it "extracts values with pattern matching" do
      success_result = Mu::Action::Success.new("test value", meta: { action: "test_success" })
      failure_result = Mu::Action::Failure.new("test error", meta: { action: "test_failure" })

      success_value, success_meta_action =
        case success_result
        in Mu::Action::Success(value:, meta: { action: })
          [value, action]
        else
          [nil, nil]
        end

      failure_error, failure_meta_action =
        case failure_result
        in Mu::Action::Failure(error:, meta: { action: })
          [error, action]
        else
          [nil, nil]
        end

      expect(success_value).to eq("test value")
      expect(success_meta_action).to eq("test_success")
      expect(failure_error).to eq("test error")
      expect(failure_meta_action).to eq("test_failure")
    end
  end
end
