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

    it "includes the feature modules" do
      expect(action_class.included_modules).to include(
        Mu::Action::Context, Mu::Action::Metadata, Mu::Action::Hooks, Mu::Action::Failures
      )
    end
  end

  # An action class resolves the constants of Mu::Action by their bare name,
  # ahead of the application's top-level constants, so each constant added
  # there is a name applications can no longer use unqualified in an action.
  describe "constants seen by action classes" do
    it "are a known list" do
      expect(Mu::Action.constants).to contain_exactly(
        :CONTEXT_KEY, :ClassMethods, :Context, :Failure, :FailureError, :Failures,
        :Hooks, :Metadata, :Result, :Success, :VERSION
      )
    end

    it "do not hide an application's Configuration" do
      application_constant = stub_const("Configuration", Module.new)

      expect(action_class.class_eval("Configuration", __FILE__, __LINE__)).to be(application_constant)
    end

    it "let an application reach its own constant with a leading ::" do
      application_constant = stub_const("Result", Class.new)

      expect(action_class.class_eval("Result", __FILE__, __LINE__)).to be(Mu::Action::Result)
      expect(action_class.class_eval("::Result", __FILE__, __LINE__)).to be(application_constant)
    end
  end

  describe "including Mu::Action again" do
    it "changes nothing in the same class" do
      action_class.before { meta[:hooked] = true }
      props = action_class.literal_properties.map(&:name)

      action_class.include(Mu::Action)

      expect(action_class.literal_properties.map(&:name)).to eq(props)
      expect(action_class.call(name: "Test").meta).to include(hooked: true)
    end

    it "changes nothing in a subclass" do
      subclass = Class.new(action_class) { include Mu::Action }

      expect(subclass.literal_properties.map(&:name)).to eq(action_class.literal_properties.map(&:name))
      expect(subclass.call!(name: "Test")).to eq(action_class.call!(name: "Test"))
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

      it "includes the details in the failure" do
        expect do
          instance.Failure("test error", extra: "info")
        end.to raise_error(Mu::Action::FailureError) { expect(_1.details).to eq(extra: "info") }
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

    it "runs the parent's initialize in a subclass without props" do
      parent = Class.new do
        include Mu::Action

        prop :amount, Integer

        def initialize(...)
          super
          @cents = @amount * 100
        end

        def call = Success(@cents)
      end

      expect(Class.new(parent).call!(amount: 2)).to eq(200)
    end
  end

  describe "reserved props" do
    def declaring(name, parent: nil, &declaration)
      declaration ||= proc { prop name, String }
      Class.new(parent || Object) do
        include Mu::Action unless parent

        class_eval(&declaration)
      end
    end

    it "rejects a prop named meta or context" do
      expect { declaring(:meta) }.to raise_error(ArgumentError, /the meta prop is reserved by Mu::Action/)
      expect { declaring(:context) }.to raise_error(ArgumentError, /the context prop is reserved by Mu::Action/)
    end

    it "rejects them in a subclass" do
      parent = Class.new { include Mu::Action }

      expect { declaring(:context, parent:) }.to raise_error(ArgumentError, /context prop is reserved/)
    end

    it "rejects them when declared with prop?" do
      expect { declaring(:meta) { prop? :meta, Hash } }.to raise_error(ArgumentError, /meta prop is reserved/)
    end

    it "rejects a class that declared one before including Mu::Action" do
      early = proc do
        Class.new do
          extend Literal::Properties

          prop :context, String
          include Mu::Action
        end
      end

      expect(&early).to raise_error(ArgumentError, /context prop is reserved/)
    end

    it "accepts other prop names" do
      expect(declaring(:metadata).literal_properties.map(&:name)).to include(:metadata)
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
