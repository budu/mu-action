# frozen_string_literal: true

RSpec.describe "Mu::Action failures" do
  def action(&) = Class.new { include Mu::Action }.tap { _1.class_eval(&) }

  around do |example|
    handler = Mu::Action.on_undeclared_failure
    example.run
  ensure
    Mu::Action.on_undeclared_failure = handler
  end

  describe "details" do
    let(:action_class) do
      action do
        prop :name, String
        def call = Failure(:invalid, field: :name, reason: "blank")
      end
    end

    it "stores the keyword arguments of Failure as details" do
      result = action_class.call(name: "")

      expect(result.error).to eq(:invalid)
      expect(result.details).to eq(field: :name, reason: "blank")
    end

    it "keeps the metadata for diagnostics only" do
      result = action_class.call(name: "")

      expect(result.meta.keys).to contain_exactly(:class, :props, :failure_error)
    end

    it "supports pattern matching on details" do
      matched =
        case action_class.call(name: "")
        in Mu::Action::Failure(error: :invalid, details: { field: })
          field
        end

      expect(matched).to eq(:name)
    end

    it "defaults to empty details" do
      expect(Mu::Action::Failure.new(:oops).details).to eq({})
    end
  end

  describe "call!" do
    let(:action_class) do
      action do
        def call = Failure(:invalid, field: :name)
      end
    end

    it "raises a FailureError carrying the error, details and failure result" do
      expect { action_class.call! }.to raise_error(Mu::Action::FailureError) do |error|
        expect(error.error).to eq(:invalid)
        expect(error.details).to eq(field: :name)
        expect(error.failure).to be_a(Mu::Action::Failure)
        expect(error.failure.meta[:class]).to eq(action_class)
      end
    end

    it "keeps the original FailureError as the cause" do
      expect { action_class.call! }.to raise_error(Mu::Action::FailureError) do |error|
        expect(error.cause).to be_a(Mu::Action::FailureError)
        expect(error.cause.backtrace.first).to include("Failure")
      end
    end
  end

  describe "declarations" do
    let(:action_class) do
      action do
        failure :site_disabled
        failure :invalid, errors: Array
        failure :not_found, id: _Nilable(Integer)

        prop :code, Symbol
        prop :details, Hash, default: -> { {} }

        def call = Failure(@code, **@details)
      end
    end

    it "lists the declared failures with their details types" do
      expect(action_class.failures.keys).to eq(%i[site_disabled invalid not_found])
      expect(action_class.failures[:invalid]).to eq(errors: Array)
    end

    it "accepts declared failures" do
      result = action_class.call(code: :invalid, details: { errors: ["blank"] })

      expect(result.error).to eq(:invalid)
      expect(result.details).to eq(errors: ["blank"])
    end

    it "accepts a missing detail when its type allows nil" do
      expect(action_class.call(code: :not_found).error).to eq(:not_found)
    end

    it "raises on an undeclared failure" do
      expect { action_class.call(code: :boom) }
        .to raise_error(ArgumentError, /undeclared failure :boom/)
    end

    it "raises on a detail of the wrong type" do
      expect { action_class.call(code: :invalid, details: { errors: "blank" }) }
        .to raise_error(ArgumentError, /detail :errors of failure :invalid must be Array, got "blank"/)
    end

    it "raises on a missing detail" do
      expect { action_class.call(code: :invalid) }
        .to raise_error(ArgumentError, /detail :errors of failure :invalid must be Array, got nil/)
    end

    it "raises on an unexpected detail" do
      expect { action_class.call(code: :site_disabled, details: { why: "off" }) }
        .to raise_error(ArgumentError, /unexpected details \[:why\] for failure :site_disabled/)
    end

    it "accepts any failure when the action declares none" do
      undeclared = action { def call = Failure(:anything, at: :all) }

      expect(undeclared.failures).to be_empty
      expect(undeclared.call.error).to eq(:anything)
    end

    it "declares several codes at once" do
      multi = action { failure :one, :two }

      expect(multi.failures).to eq(one: {}, two: {})
    end

    it "rejects details declared for several codes" do
      expect { action { failure :one, :two, field: Symbol } }
        .to raise_error(ArgumentError, /single failure/)
    end

    it "rejects an empty declaration" do
      expect { action { failure } }.to raise_error(ArgumentError, /code or from:/)
    end

    it "rejects details declared without a code" do
      expect { action { failure errors: Array } }.to raise_error(ArgumentError, /code or from:/)
    end

    it "accepts a detail named from" do
      transition = action do
        failure :invalid_transition, from: Symbol, to: Symbol

        prop :from, Symbol
        prop :to, Symbol

        def call = Failure(:invalid_transition, from: @from, to: @to)
      end

      expect(transition.failures).to eq(invalid_transition: { from: Symbol, to: Symbol })
      expect(transition.call(from: :draft, to: :draft).details).to eq(from: :draft, to: :draft)
    end

    it "inherits declarations without sharing them" do
      parent = action { failure :parent_failure }
      child = Class.new(parent) { failure :child_failure }

      expect(child.failures.keys).to eq(%i[parent_failure child_failure])
      expect(parent.failures.keys).to eq(%i[parent_failure])
    end

    it "follows the declarations added to the parent after the subclass was defined" do
      parent = action { failure :parent_failure }
      child = Class.new(parent) { failure :child_failure }
      other = action { failure :from_other }
      parent.failure :added_later
      parent.failure from: other

      expect(child.failures.keys).to contain_exactly(:parent_failure, :added_later, :from_other, :child_failure)
      expect(parent.failures.keys).not_to include(:child_failure)
    end

    it "checks the failures of a subclass once its parent declares one" do
      parent = action { def call = Failure(:anything) }
      child = Class.new(parent)

      expect(child.call.error).to eq(:anything)

      parent.failure :something_else

      expect { child.call }.to raise_error(ArgumentError, /undeclared failure :anything/)
    end
  end

  describe "on_undeclared_failure" do
    let(:action_class) do
      action do
        failure :declared
        def call = Failure(:undeclared, info: 1)
      end
    end

    it "defaults to :raise" do
      expect(Mu::Action.on_undeclared_failure).to eq(:raise)
    end

    it "calls a callable handler and lets the failure through" do
      calls = []
      Mu::Action.on_undeclared_failure = ->(*args) { calls << args }

      result = action_class.call

      expect(result.error).to eq(:undeclared)
      expect(calls).to match([[be_a(action_class), :undeclared, { info: 1 }]])
    end

    it "is called for a failure of a nested action that the outer action does not allow" do
      calls = []
      Mu::Action.on_undeclared_failure = ->(_action, error, details) { calls << [error, details] }
      nested = action { def call = Failure(:nested_failed, why: "no") }
      outer = action do
        failure :other
        define_method(:call) { Success(nested.call!) }
      end

      expect(outer.call.error).to eq(:nested_failed)
      expect(calls).to eq([[:nested_failed, { why: "no" }]])
    end

    it "rejects other values" do
      expect { Mu::Action.on_undeclared_failure = :log }
        .to raise_error(ArgumentError, /:raise or respond to #call/)
    end
  end

  describe "propagation through call!" do
    let(:inner) do
      action do
        failure :invalid, errors: Array
        prop :secret, String
        def call = Failure(:invalid, errors: ["blank"])
      end
    end

    def outer_for(_inner, &declarations)
      action do
        class_eval(&declarations) if declarations
        prop :inner, Class
        define_method(:call) { Success(@inner.call!(secret: "s3cret")) }
      end
    end

    it "keeps the inner error and details" do
      result = outer_for(inner).call(inner:)

      expect(result.error).to eq(:invalid)
      expect(result.details).to eq(errors: ["blank"])
    end

    it "stores the inner failure as the cause instead of merging its metadata" do
      outer = outer_for(inner)
      result = outer.call(inner:)

      expect(result.meta[:class]).to eq(outer)
      expect(result.meta[:props]).not_to have_key(:secret)
      expect(result.meta[:cause]).to be_a(Mu::Action::Failure)
      expect(result.meta[:cause].meta[:class]).to eq(inner)
    end

    it "chains causes across several levels" do
      middle = outer_for(inner)
      top = action do
        prop :middle, Class
        prop :inner, Class
        def call = Success(@middle.call!(inner: @inner))
      end

      result = top.call(middle:, inner:)

      expect(result.error).to eq(:invalid)
      expect(result.meta[:cause].meta[:class]).to eq(middle)
      expect(result.meta[:cause].meta[:cause].meta[:class]).to eq(inner)
    end

    it "accepts failures from actions declared with from:" do
      source = inner
      outer = outer_for(inner) { failure from: source }

      expect(outer.failures).to eq(invalid: { errors: Array })
      expect(outer.call(inner:).error).to eq(:invalid)
    end

    it "accepts several from: actions at once" do
      first = action { failure :first_failed }
      second = action { failure :second_failed }
      both = action { failure from: [first, second] }

      expect(both.failures.keys).to eq(%i[first_failed second_failed])
    end

    it "rejects a from: that is not an action class" do
      expect { action { failure from: 42 } }
        .to raise_error(ArgumentError, /from: expects action classes, got \[42\]/)
      expect { action { failure from: [String] } }
        .to raise_error(ArgumentError, /from: expects action classes, got \[String\]/)
    end

    it "lists the failures of actions that name each other" do
      first = action { failure :first_failed }
      second = action { failure :second_failed }
      first.failure from: second
      second.failure from: first

      expect(first.failures.keys).to contain_exactly(:first_failed, :second_failed)
      expect(second.failures.keys).to contain_exactly(:first_failed, :second_failed)
    end

    it "lets its own declaration win over a from: action's" do
      source = action { failure :invalid, errors: Array }
      overriding = action do
        failure from: source
        failure :invalid, reason: String
      end

      expect(overriding.failures).to eq(invalid: { reason: String })
    end

    it "checks its own failures once it names a from: action" do
      source = inner
      strict = action do
        failure from: source
        def call = Failure(:something_else)
      end

      expect { strict.call }.to raise_error(ArgumentError, /undeclared failure :something_else/)
    end

    it "accepts the failures of a subclass of a from: action" do
      source = action do
        prop :secret, String
        def call = Failure(:whatever)
      end
      subclass = Class.new(source)
      outer = outer_for(subclass) { failure from: source }

      expect(outer.call(inner: subclass).error).to eq(:whatever)
    end

    it "accepts any failure from a from: action that declares none" do
      source = action do
        prop :secret, String
        def call = Failure(:whatever)
      end
      outer = outer_for(source) { failure from: source }

      expect(outer.call(inner: source).error).to eq(:whatever)
    end

    it "accepts a propagated failure whose code the outer action declares" do
      outer = outer_for(inner) { failure :invalid, errors: Array }

      expect(outer.call(inner:).error).to eq(:invalid)
    end

    it "raises on a propagated failure the outer action does not allow" do
      outer = outer_for(inner) { failure :other }

      expect { outer.call(inner:) }.to raise_error(ArgumentError, /undeclared failure :invalid/)
    end

    it "lets around hooks see the inner failure as an exception" do
      seen = []
      outer = outer_for(inner)
      outer.around do |_action, chain|
        chain.call
      rescue Mu::Action::FailureError => e
        seen << e.error
        raise
      end

      outer.call(inner:)

      expect(seen).to eq([:invalid])
    end
  end

  describe "propagation through run!" do
    let(:inner) do
      action { def call = Failure(:inner_failed, why: "no") }
    end

    def running(inner, &declarations)
      action do
        class_eval(&declarations) if declarations
        define_method(:call) { Success(inner.new.run!.value) }
      end
    end

    it "raises a FailureError that carries the failure" do
      expect { inner.new.run! }.to raise_error(Mu::Action::FailureError) do |error|
        expect(error.error).to eq(:inner_failed)
        expect(error.details).to eq(why: "no")
        expect(error.failure.meta[:class]).to eq(inner)
        expect(error.cause).to be_a(Mu::Action::FailureError)
      end
    end

    it "returns the Success when the action succeeds" do
      succeeding = action { def call = Success(:done) }

      expect(succeeding.new.run!).to be_a(Mu::Action::Success).and have_attributes(value: :done)
    end

    it "makes the failure of the inner action the failure of the outer one, with its cause" do
      outer = running(inner)
      result = outer.call

      expect(result.error).to eq(:inner_failed)
      expect(result.details).to eq(why: "no")
      expect(result.meta[:class]).to eq(outer)
      expect(result.meta[:cause].meta[:class]).to eq(inner)
    end

    it "is checked against the failures the outer action declares" do
      outer = running(inner) { failure :other }

      expect { outer.call }.to raise_error(ArgumentError, /undeclared failure :inner_failed/)
    end

    it "accepts the failures of a from: action" do
      source = inner
      outer = running(inner) { failure from: source }

      expect(outer.call.error).to eq(:inner_failed)
    end
  end
end
