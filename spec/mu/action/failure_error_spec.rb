# frozen_string_literal: true

RSpec.describe Mu::Action::FailureError do
  describe "initialization" do
    it "accepts an error message" do
      failure = described_class.new("Something went wrong")

      expect(failure.error).to eq("Something went wrong")
      expect(failure.message).to eq("Something went wrong")
      expect(failure.meta).to eq({})
    end

    it "accepts an error object" do
      original_error = StandardError.new("Original error")
      failure = described_class.new(original_error)

      expect(failure.error).to eq(original_error)
      expect(failure.message).to eq(original_error.message)
    end

    it "accepts metadata" do
      meta = { foo: :bar }
      failure = described_class.new("Error", meta:)

      expect(failure.meta).to eq(meta)
    end

    it "defaults to empty metadata hash" do
      failure = described_class.new("Error")
      expect(failure.meta).to eq({})
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end
  end
end
