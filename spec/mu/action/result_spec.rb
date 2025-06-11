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
