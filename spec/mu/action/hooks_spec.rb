# frozen_string_literal: true

RSpec.describe "Mu::Action hooks" do
  let(:action_class) do
    Class.new do
      include Mu::Action

      prop :name, String

      def call
        Success("Hello #{@name}")
      end
    end
  end

  describe "before hooks" do
    it "executes before hooks before call" do
      action_class.before { meta[:before_executed] = true }

      result = action_class.call(name: "Test")

      expect(result.meta).to include(before_executed: true)
    end

    it "executes multiple before hooks in order" do
      order = []
      action_class.before { order << :first }
      action_class.before { order << :second }

      action_class.call(name: "Test")

      expect(order).to eq(%i[first second])
    end

    it "allows access to instance variables in hooks" do
      action_class.before { meta[:name_from_hook] = @name }

      result = action_class.call(name: "Alice")

      expect(result.meta).to include(name_from_hook: "Alice")
    end

    it "can modify meta in before hooks" do
      action_class.before do
        meta[:original_name] = @name
        instance_variable_set(:@name, "Modified #{@name}")
      end

      result = action_class.call(name: "Bob")

      expect(result.meta).to include(original_name: "Bob")
      expect(result.value).to eq("Hello Modified Bob")
    end

    it "supports method-based before hooks" do
      action_class.class_eval do
        def record_before
          meta[:before_method] = true
        end
      end

      action_class.before :record_before

      result = action_class.call(name: "Test")

      expect(result.meta).to include(before_method: true)
    end
  end

  describe "after hooks" do
    it "executes after hooks after call" do
      action_class.after { meta[:after_executed] = true }

      result = action_class.call(name: "Test")

      expect(result.meta).to include(after_executed: true)
    end

    it "executes multiple after hooks in order" do
      order = []
      action_class.after { order << :first }
      action_class.after { order << :second }

      action_class.call(name: "Test")

      expect(order).to eq(%i[first second])
    end

    describe "when the action does not succeed" do
      let(:ran) { [] }

      before do
        events = ran
        action_class.after { events << :after }
      end

      it "does not run them when call fails" do
        action_class.define_method(:call) { Failure(:nope) }

        expect(action_class.call(name: "Test").error).to eq(:nope)
        expect(ran).to be_empty
      end

      it "does not run them when a before hook fails" do
        action_class.before { Failure(:not_allowed) }

        expect(action_class.call(name: "Test").error).to eq(:not_allowed)
        expect(ran).to be_empty
      end

      it "does not run them when call raises" do
        action_class.define_method(:call) { raise "boom" }

        expect { action_class.call(name: "Test") }.to raise_error("boom")
        expect(ran).to be_empty
      end
    end

    it "supports method-based after hooks" do
      action_class.class_eval do
        def record_after
          meta[:after_method] = true
        end
      end

      action_class.after :record_after

      result = action_class.call(name: "Test")

      expect(result.meta).to include(after_method: true)
    end
  end

  describe "around hooks" do
    it "executes around hooks wrapping the call" do
      action_class.around do |action, chain|
        action.meta[:before_chain] = true
        result = chain.call
        action.meta[:after_chain] = true
        result
      end

      result = action_class.call(name: "Test")

      expect(result.meta).to include(
        before_chain: true,
        after_chain: true
      )
    end

    it "can modify the result in around hooks" do
      action_class.around do |action, chain|
        result = chain.call
        action.Success("Modified: #{result.value}")
      end

      result = action_class.call!(name: "Test")

      expect(result).to eq("Modified: Hello Test")
    end

    it "executes multiple around hooks in nested order" do
      action_class.around do |action, chain|
        action.meta[:outer_before] = true
        result = chain.call
        action.meta[:outer_after] = true
        result
      end

      action_class.around do |action, chain|
        action.meta[:inner_before] = true
        result = chain.call
        action.meta[:inner_after] = true
        result
      end

      result = action_class.call(name: "Test")

      expect(result.meta).to include(
        outer_before: true,
        inner_before: true,
        inner_after: true,
        outer_after: true
      )
    end

    it "can short-circuit execution in around hooks" do
      action_class.around do |action, chain|
        if action.instance_variable_get(:@name) == "skip"
          Success("Skipped execution")
        else
          chain.call
        end
      end

      normal_result = action_class.call!(name: "normal")
      skipped_result = action_class.call!(name: "skip")

      expect(normal_result).to eq("Hello normal")
      expect(skipped_result).to eq("Skipped execution")
    end

    it "rejects an around hook that does not return a result" do
      action_class.around do |chain|
        chain.call
        meta[:finished] = true
      end

      expect { action_class.call(name: "Test") }
        .to raise_error(TypeError, /an around hook returned true\. It must return Success/)
    end

    it "does not run the after hooks when an around hook does not return a result" do
      ran = []
      action_class.around { |chain| chain.call && nil }
      action_class.after { ran << :after }

      expect { action_class.call(name: "Test") }.to raise_error(TypeError, /an around hook returned nil/)
      expect(ran).to be_empty
    end

    it "turns the Failure of another action returned by an around hook into its own failure" do
      guard = Class.new do
        include Mu::Action

        def call = Failure(:forbidden)
      end
      action_class.around { |_chain| guard.call }

      result = action_class.call(name: "Test")

      expect(result.error).to eq(:forbidden)
      expect(result.meta[:class]).to eq(action_class)
      expect(result.meta[:cause].meta[:class]).to eq(guard)
    end

    it "passes the chain to an around block that takes one parameter" do
      log = []
      action_class.around { |chain| chain.call.tap { log << :outer } }
      action_class.around { |_action, chain| chain.call.tap { log << :inner } }

      expect(action_class.call!(name: "Test")).to eq("Hello Test")
      expect(log).to eq(%i[inner outer])
    end

    it "passes the chain to an around block that uses a numbered parameter" do
      action_class.around { _1.call.tap { meta[:wrapped] = true } }

      expect(action_class.call(name: "Test").meta).to include(wrapped: true)
    end

    it "passes the action and the chain to an around block that takes any number of parameters" do
      action_class.around { |*arguments| arguments.last.call.tap { meta[:same] = arguments.first.equal?(self) } }

      expect(action_class.call(name: "Test").meta).to include(same: true)
    end

    it "accepts lambdas that take the chain, or the action and the chain" do
      action_class.around(&->(chain) { chain.call.tap { meta[:one] = true } })
      action_class.around(&->(action, chain) { chain.call.tap { action.meta[:two] = true } })

      expect(action_class.call(name: "Test").meta).to include(one: true, two: true)
    end

    it "rejects an around block that takes no parameter, as it could not call the chain" do
      expect { action_class.around { :never_continues } }
        .to raise_error(ArgumentError, /around block takes the chain, or the action and the chain/)
    end

    it "does not count the keyword parameters of a method-based around hook" do
      action_class.class_eval do
        def wrap_with_label(chain, label: :default)
          meta[:label] = label
          chain.call
        end
      end

      action_class.around :wrap_with_label

      expect(action_class.call(name: "Test").meta).to include(label: :default)
    end

    it "supports method-based around hooks receiving the chain" do
      action_class.class_eval do
        def wrap_call(chain)
          meta[:before_chain_method] = true
          result = chain.call
          meta[:after_chain_method] = true
          result
        end
      end

      action_class.around :wrap_call

      result = action_class.call(name: "Test")

      expect(result.meta).to include(
        before_chain_method: true,
        after_chain_method: true
      )
    end

    it "allows method-based around hooks to use a block" do
      action_class.class_eval do
        def wrap_with_block
          meta[:method_block_before] = true
          result = yield
          meta[:method_block_after] = true
          result
        end
      end

      action_class.around :wrap_with_block

      result = action_class.call(name: "Test")

      expect(result.meta).to include(
        method_block_before: true,
        method_block_after: true
      )
    end

    it "supports method-based around hooks receiving the action and chain" do
      action_class.class_eval do
        def wrap_with_context(action, chain)
          meta[:method_chain_with_action] = (self == action)
          chain.call
        end
      end

      action_class.around :wrap_with_context

      result = action_class.call(name: "Test")

      expect(result.meta).to include(method_chain_with_action: true)
    end
  end

  describe "hook execution order" do
    it "executes hooks in the correct order: before -> around -> call -> after" do
      execution_order = []

      action_class.before { execution_order << :before }
      action_class.after { execution_order << :after }
      action_class.around do |_action, chain|
        execution_order << :around_before
        result = chain.call
        execution_order << :around_after
        result
      end

      modified_action_class = Class.new(action_class) do
        define_method :call do
          execution_order << :call
          super()
        end
      end

      modified_action_class.call(name: "Test")

      expect(execution_order).to eq(%i[before around_before call around_after after])
    end
  end

  describe "hook inheritance" do
    let(:parent_class) do
      Class.new do
        include Mu::Action

        prop :name, String

        before { meta[:parent_before] = true }
        after { meta[:parent_after] = true }
        around do |action, chain|
          action.meta[:parent_around] = true
          chain.call
        end

        def call
          Success("parent: #{@name}")
        end
      end
    end

    let(:child_class) do
      Class.new(parent_class) do
        before { meta[:child_before] = true }
        after { meta[:child_after] = true }
        around do |action, chain|
          action.meta[:child_around] = true
          chain.call
        end

        def call
          Success("child: #{@name}")
        end
      end
    end

    it "inherits hooks from parent class" do
      result = child_class.call(name: "Test")

      expect(result.meta).to include(
        parent_before: true,
        parent_after: true,
        parent_around: true,
        child_before: true,
        child_after: true,
        child_around: true
      )
    end

    it "maintains separate hook arrays for parent and child" do
      parent_class.before { meta[:parent_only] = true }
      child_class.before { meta[:child_only] = true }

      parent_result = parent_class.call(name: "Parent")
      child_result = child_class.call(name: "Child")

      expect(parent_result.meta).to include(parent_only: true)
      expect(parent_result.meta).not_to include(child_only: true)

      expect(child_result.meta).to include(child_only: true, parent_only: true)
    end

    it "follows the hooks added to the parent after the subclass was defined" do
      child_class
      parent_class.before { meta[:late_before] = true }
      parent_class.after { meta[:late_after] = true }
      parent_class.around { |chain| chain.call.tap { meta[:late_around] = true } }

      expect(child_class.call(name: "Test").meta).to include(late_before: true, late_after: true, late_around: true)
    end

    it "runs the hooks of the parent before its own, whenever they were added" do
      order = []
      child_class.before { order << :child }
      parent_class.before { order << :parent_added_later }

      child_class.call(name: "Test")

      expect(order).to eq(%i[parent_added_later child])
    end

    it "does not rely on the inherited hook of the parent class" do
      parent_class.define_singleton_method(:inherited) { |_subclass| nil }
      silent_child = Class.new(parent_class)

      expect(silent_child.call(name: "Test").meta).to include(parent_before: true, parent_around: true)
    end

    it "keeps the after and around hooks of a child out of its parent" do
      child_class.after { meta[:child_only_after] = true }
      child_class.around { |chain| chain.call.tap { meta[:child_only_around] = true } }

      parent_result = parent_class.call(name: "Parent")
      child_result = child_class.call(name: "Child")

      expect(parent_result.meta.keys).not_to include(:child_after, :child_around, :child_only_after, :child_only_around)
      expect(child_result.meta).to include(child_only_after: true, child_only_around: true)
    end
  end

  describe "hook registration" do
    it "rejects a block together with method names" do
      expect { action_class.before(:prepare) { meta[:x] = 1 } }
        .to raise_error(ArgumentError, "before hooks accept either a block or method names, not both")
    end

    it "rejects a hook without a block or a method name" do
      expect { action_class.after }.to raise_error(ArgumentError, "after hook requires a block or method name")
    end

    it "rejects a hook that is neither a block nor a name" do
      expect { action_class.around(42) }.to raise_error(ArgumentError, "Invalid around hook identifier: 42")
    end

    it "accepts several method names, given as symbols or strings" do
      action_class.class_eval do
        def first_step = meta[:steps] = [:first]
        def second_step = meta[:steps] << :second
      end

      action_class.before(:first_step, "second_step")

      expect(action_class.call(name: "Test").meta[:steps]).to eq(%i[first second])
    end

    it "reports an around hook method that does not exist when the action runs" do
      action_class.around(:missing)

      expect { action_class.call(name: "Test") }.to raise_error(NoMethodError, /Undefined hook method #missing/)
    end
  end

  describe "hook error handling" do
    it "propagates errors from before hooks" do
      action_class.before { raise StandardError, "Before hook error" }

      expect do
        action_class.call!(name: "Test")
      end.to raise_error(StandardError, "Before hook error")
    end

    it "propagates errors from before hooks through call as well" do
      action_class.before { raise StandardError, "Hook error" }

      expect do
        action_class.call(name: "Test")
      end.to raise_error(StandardError, "Hook error")
    end

    it "propagates errors from after hooks" do
      action_class.after { raise StandardError, "After hook error" }

      expect do
        action_class.call!(name: "Test")
      end.to raise_error(StandardError, "After hook error")
    end

    it "propagates errors from around hooks" do
      action_class.around { |_action, _chain| raise StandardError, "Around hook error" }

      expect do
        action_class.call!(name: "Test")
      end.to raise_error(StandardError, "Around hook error")
    end

    it "handles failures" do
      action_class.before { Failure("Failure error", hook: "before") }

      result = action_class.call(name: "Test")

      expect(result.failure?).to be true
      expect(result.error).to eq("Failure error")
      expect(result.details).to eq(hook: "before")
    end
  end
end
