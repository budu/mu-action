# frozen_string_literal: true

RSpec.describe Mu::Action::FailureError do
  describe "initialization" do
    it "accepts an error message" do
      failure = described_class.new("Something went wrong")

      expect(failure.error).to eq("Something went wrong")
      expect(failure.message).to eq("Something went wrong")
      expect(failure.details).to eq({})
      expect(failure.failure).to be_nil
    end

    it "accepts an error object" do
      original_error = StandardError.new("Original error")
      failure = described_class.new(original_error)

      expect(failure.error).to eq(original_error)
      expect(failure.message).to eq(original_error.message)
    end

    it "accepts details" do
      failure = described_class.new(:invalid, details: { field: :name })

      expect(failure.details).to eq(field: :name)
    end

    it "accepts the failure result" do
      result = Mu::Action::Failure.new(:invalid)
      failure = described_class.new(:invalid, failure: result)

      expect(failure.failure).to be(result)
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end
  end
end
