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

  it "is declared when Mu::Action is included" do
    expect(action { def call = Success(:ok) }.literal_properties.map(&:name)).to include(:context)
  end

  describe "in the default of another prop" do
    def localized(parent = nil)
      Class.new(parent || Object) do
        include Mu::Action unless parent

        prop :locale, Symbol, default: -> { context ? context[:locale] : :en }

        def call = Success(@locale)
      end
    end

    it "is available" do
      expect(localized.call!(context: { locale: :fr })).to eq(:fr)
      expect(localized.call!).to eq(:en)
    end

    it "is available in a subclass, whether or not the parent was called first" do
      fresh_parent = action { def call = Success(:ok) }
      called_parent = action { def call = Success(:ok) }
      called_parent.call

      expect(localized(fresh_parent).call!(context: { locale: :fr })).to eq(:fr)
      expect(localized(called_parent).call!(context: { locale: :fr })).to eq(:fr)
    end
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

      expect(reader.call.value).to eq([nil])
    end

    it "is restored after a failure" do
      failing = action { def call = Failure(:boom) }

      failing.call(context: :ctx)

      expect(reader.call.value).to eq([nil])
    end

    it "is restored after an exception" do
      raising = action { def call = raise("boom") }

      expect { raising.call(context: :ctx) }.to raise_error("boom")
      expect(reader.call.value).to eq([nil])
    end
  end

  describe "outside the call stack" do
    # Runs the block inside an action that has the given context.
    def running(context, &block)
      action { define_method(:call) { Success(block.call) } }.call!(context:)
    end

    it "is not inherited by a thread started by the action" do
      seen = running(:ctx) { Thread.new { reader.call!.first }.value }

      expect(seen).to be_nil
    end

    it "is not inherited by a fiber started by the action" do
      seen = running(:ctx) { Fiber.new { reader.call!.first }.resume }

      expect(seen).to be_nil
    end

    it "can be handed to another thread explicitly" do
      inner = reader
      handing = action do
        define_method(:call) { Success(Thread.new { inner.call!(context:).first }.value) }
      end

      expect(handing.call!(context: :ctx)).to eq(:ctx)
    end

    it "does not stay on a thread that outlives the action" do
      jobs = Queue.new
      worker = nil
      on_worker = lambda do |&job|
        worker ||= Thread.new { loop { jobs.pop.then { |task, out| out << task.call } } }
        jobs << [job, out = Queue.new]
        out.pop
      end

      running({ actor: "alice" }) { on_worker.call { reader.call!.first } }

      expect(running({ actor: "bob" }) { on_worker.call { reader.call!.first } }).to be_nil
      expect(on_worker.call { reader.call!.first }).to be_nil
    ensure
      worker&.kill
    end

    it "is kept apart between threads that run actions at the same time" do
      inner = reader
      ready = Queue.new
      waiting = action do
        prop :gate, Queue

        define_method(:call) do
          ready << true
          @gate.pop
          Success(inner.call!.first)
        end
      end
      gates = { a: Queue.new, b: Queue.new }
      threads = gates.map { |name, gate| Thread.new { waiting.call!(context: name, gate:) } }

      2.times { ready.pop }
      gates.each_value { _1 << true }

      expect(threads.map(&:value)).to eq(%i[a b])
    end
  end
end
