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

  describe "message" do
    it "names the keys of the details, not their values" do
      failure = described_class.new(:invalid, details: { errors: ["name is blank"], email: "jane@example.com" })

      expect(failure.message).to eq("invalid (details: errors, email)")
    end

    it "names the action when the error carries its failure" do
      stub_const("CreateUser", Class.new do
        include Mu::Action

        def call = Failure(:user_exists, email: "jane@example.com")
      end)

      expect { CreateUser.call! }.to raise_error(described_class, "CreateUser failed: user_exists (details: email)")
      expect { CreateUser.new.run! }.to raise_error(described_class, "CreateUser failed: user_exists (details: email)")
    end

    it "leaves out the name of an anonymous action" do
      anonymous = Class.new do
        include Mu::Action

        def call = Failure(:nope)
      end

      expect { anonymous.call! }.to raise_error(described_class, "nope")
    end

    it "uses the message of an exception given as the error" do
      failure = described_class.new(IOError.new("disk full"), details: { path: "/tmp/x" })

      expect(failure.message).to eq("disk full (details: path)")
    end
  end

  describe "inheritance" do
    it "inherits from StandardError" do
      expect(described_class).to be < StandardError
    end
  end
end
