# frozen_string_literal: true

RSpec.describe "Mu::Action context" do
  def action(&) = Class.new { include Mu::Action }.tap { _1.class_eval(&) }

  let(:reader) do
    action do
      prop :seen, Array, default: -> { [] }

      before { @seen << [:before, context] }

      def call = Success([context])
    end
  end

  it "is nil by default" do
    expect(reader.new.context).to be_nil
    expect(reader.call.value).to eq([nil])
  end

  it "is available to hooks and call" do
    seen = []
    result = reader.call(seen:, context: { actor: "nick" })

    expect(result.value).to eq([{ actor: "nick" }])
    expect(seen).to eq([[:before, { actor: "nick" }]])
  end

  it "accepts any object" do
    ctx = Struct.new(:actor, :channel).new("nick", :api)

    expect(reader.call(context: ctx).value.first).to be(ctx)
  end

  it "is recorded in the metadata when given" do
    result = reader.call(context: { actor: "nick" })

    expect(result.meta[:context]).to eq(actor: "nick")
    expect(result.meta[:props]).not_to have_key(:context)
  end

  it "is left out of the metadata when absent" do
    expect(reader.call.meta).not_to have_key(:context)
  end

  describe "nested actions" do
    let(:outer) do
      inner_class = reader
      action do
        define_method(:inner_class) { inner_class }
        def call = Success(inner_class.call!)
      end
    end

    it "inherit the context of the calling action" do
      expect(outer.call(context: { actor: "nick" }).value).to eq([{ actor: "nick" }])
    end

    it "inherit it through several levels" do
      middle = outer
      top = action do
        define_method(:middle) { middle }
        def call = Success(middle.call!)
      end

      expect(top.call(context: :ctx).value).to eq([:ctx])
    end

    it "inherit it in hooks" do
      inner_class = reader
      seen = []
      hooked = action do
        before { seen.concat(inner_class.call!) }
        def call = Success(:ok)
      end

      hooked.call(context: :ctx)

      expect(seen).to eq([:ctx])
    end

    it "can override it explicitly" do
      inner_class = reader
      overriding = action do
        define_method(:call) { Success(inner_class.call!(context: :other)) }
      end

      expect(overriding.call(context: :ctx).value).to eq([:other])
    end

    it "is restored after the action runs" do
      outer.call(context: :ctx)

      expect(Fiber[Mu::Action::CONTEXT_KEY]).to be_nil
      expect(reader.call.value).to eq([nil])
    end

    it "is restored after a failure" do
      failing = action { def call = Failure(:boom) }

      failing.call(context: :ctx)

      expect(Fiber[Mu::Action::CONTEXT_KEY]).to be_nil
    end
  end
end
