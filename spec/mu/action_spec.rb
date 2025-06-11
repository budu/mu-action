# frozen_string_literal: true

RSpec.describe Mu::Action do
  let(:action_class) do
    Class.new do
      include Mu::Action

      prop :name, String
      prop :age, Integer, default: 42

      def call = Success("Hello #{@name}, age #{@age}")
    end
  end

  let(:failing_action_class) do
    Class.new do
      include Mu::Action

      def call = Failure("Something went wrong")
    end
  end

  describe "module inclusion" do
    it "extends the class with Literal::Properties" do
      expect(action_class.singleton_class.included_modules).to include(Literal::Properties)
    end

    it "extends the class with ClassMethods" do
      expect(action_class.singleton_class.included_modules).to include(Mu::Action::ClassMethods)
    end

    it "includes Initializer module" do
      expect(action_class.included_modules).to include(Mu::Action::Initializer)
    end
  end

  describe ".call" do
    it "returns successful result" do
      result = action_class.call(name: "Alice")

      expect(result).to be_a(Mu::Action::Success)
      expect(result.success?).to be true
      expect(result.value).to eq("Hello Alice, age 42")
    end

    it "returns failure result when action fails" do
      result = failing_action_class.call

      expect(result).to be_a(Mu::Action::Failure)
      expect(result.failure?).to be true
      expect(result.error).to eq("Something went wrong")
    end
  end

  describe ".call!" do
    it "calls run! and unwrap result" do
      result = action_class.call!(name: "Charlie")

      expect(result).to eq("Hello Charlie, age 42")
    end

    it "raises FailureError exception when action fails" do
      expect do
        failing_action_class.call!
      end.to raise_error(Mu::Action::FailureError, "Something went wrong")
    end
  end

  describe "#run" do
    let(:instance) { action_class.new(name: "David") }

    it "returns success result when call succeeds" do
      result = instance.run

      expect(result).to be_a(Mu::Action::Success)
      expect(result.success?).to be true
      expect(result.value).to eq("Hello David, age 42")
    end

    it "catches FailureError exceptions and returns failure result" do
      failing_instance = failing_action_class.new
      result = failing_instance.run

      expect(result).to be_a(Mu::Action::Failure)
      expect(result.failure?).to be true
      expect(result.error).to eq("Something went wrong")
    end
  end

  describe "#run!" do
    let(:instance) { action_class.new(name: "Eve") }

    it "returns result object when successful" do
      result = instance.run!

      expect(result).to be_a(Mu::Action::Success)
      expect(result.success?).to be true
      expect(result.value).to eq("Hello Eve, age 42")
    end

    it "raises FailureError exception when action fails" do
      expect do
        failing_action_class.new.run!
      end.to raise_error(Mu::Action::FailureError, "Something went wrong")
    end
  end

  describe "Success and Failure methods" do
    let(:instance) { action_class.new(name: "Frank") }

    describe "#Success" do
      it "creates a success result with the given value" do
        result = instance.Success("test value")

        expect(result).to be_a(Mu::Action::Success)
        expect(result.success?).to be true
        expect(result.value).to eq("test value")
        expect(result.meta).to eq(instance.meta)
      end
    end

    describe "#Failure" do
      it "raises a FailureError exception with the given error" do
        expect do
          instance.Failure("test error")
        end.to raise_error(Mu::Action::FailureError, "test error")
      end

      it "includes additional metadata in the failure" do
        instance.Failure("test error", extra: "info")
      rescue Mu::Action::FailureError => e
        expect(e.meta).to include(extra: "info")
      end
    end
  end

  describe "abstract #call method" do
    let(:abstract_action_class) do
      Class.new do
        include Mu::Action
      end
    end

    it "raises NotImplementedError when call is not implemented" do
      expect do
        abstract_action_class.new.run!
      end.to raise_error(NotImplementedError, "You must implement the call method")
    end
  end

  describe "inheritance" do
    let(:parent_class) do
      Class.new do
        include Mu::Action

        prop :base_prop, String, default: "base"

        def call = Success("parent result")
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        prop :child_prop, String, default: "child"

        def call = Success("child result: #{@base_prop}, #{@child_prop}")
      end
    end

    it "inherits properties from parent" do
      instance = child_class.new

      expect(instance.instance_variable_get(:@base_prop)).to eq("base")
      expect(instance.instance_variable_get(:@child_prop)).to eq("child")
    end
  end

  describe "pattern matching with call" do
    it "allows pattern matching on Success results" do
      result = action_class.call(name: "Foobar")

      extracted = case result
                  in Mu::Action::Success(value:, meta: { props: })
                    [value, props]
                  else
                    "no match"
                  end

      expect(extracted).to eq(["Hello Foobar, age 42", { age: 42, name: "Foobar" }])
    end

    it "allows pattern matching on Failure results" do
      result = failing_action_class.call

      extracted = case result
                  in Mu::Action::Failure(error:, meta: { props: })
                    [error, props]
                  else
                    "no match"
                  end

      expect(extracted).to eq(["Something went wrong", {}])
    end
  end

  describe "version" do
    it "has a version number" do
      expect(Mu::Action::VERSION).not_to be_nil
    end
  end
end
