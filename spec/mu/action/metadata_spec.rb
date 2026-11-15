# frozen_string_literal: true

RSpec.describe "Mu::Action metadata and property tracking" do
  let(:action_class) do
    Class.new do
      include Mu::Action

      prop :name, String
      prop :age, Integer, default: 25
      prop :optional, _Nilable(String), default: nil

      def call
        Success("processed")
      end
    end
  end

  describe "metadata initialization" do
    it "initializes meta with class and props information" do
      instance = action_class.new(name: "Test")
      expect(instance.meta).to include(
        class: action_class,
        props: hash_including(name: "Test", age: 25, optional: nil)
      )
    end

    it "adds meta property automatically when the class is instantiated" do
      action_class.new(name: "Test") # Trigger meta property addition
      expect(action_class.literal_properties.map(&:name)).to include(:meta)
    end

    it "maintains separate meta instances for different objects" do
      instance1 = action_class.new(name: "First")
      instance2 = action_class.new(name: "Second")

      instance1.meta[:test] = "first"
      instance2.meta[:test] = "second"

      expect(instance1.meta[:test]).to eq("first")
      expect(instance2.meta[:test]).to eq("second")
    end
  end

  describe "property tracking" do
    it "tracks class information in metadata" do
      instance = action_class.new(name: "Test")
      expect(instance.meta[:class]).to eq(action_class)
    end

    it "tracks all property values in metadata" do
      instance = action_class.new(name: "Alice", age: 30)

      expect(instance.meta[:props]).to include(
        name: "Alice",
        age: 30,
        optional: nil
      )
    end

    it "excludes meta property from props tracking" do
      instance = action_class.new(name: "Test")
      expect(instance.meta[:props]).not_to have_key(:meta)
    end

    it "tracks default values in properties" do
      instance = action_class.new(name: "Test")

      expect(instance.meta[:props]).to include(
        name: "Test",
        age: 25,
        optional: nil
      )
    end

    it "updates property tracking when properties change" do
      instance = action_class.new(name: "Original")
      original_props = instance.meta[:props].dup

      instance.instance_variable_set(:@name, "Modified")

      # Properties are captured at initialization, so they don't auto-update
      expect(instance.meta[:props]).to eq(original_props)
      expect(original_props[:name]).to eq("Original")
    end
  end

  describe "metadata propagation" do
    it "includes metadata in successful results" do
      result = action_class.call(name: "Test", age: 35)

      expect(result.meta).to include(
        class: action_class,
        props: hash_including(name: "Test", age: 35, optional: nil)
      )
    end

    it "includes metadata in failed results" do
      failing_action = Class.new do
        include Mu::Action

        prop :value, String

        def call = Failure("failed")
      end

      result = failing_action.call(value: "test")

      expect(result.meta).to include(
        class: failing_action,
        props: hash_including(value: "test")
      )
    end

    it "keeps Failure details out of metadata" do
      action_with_details = Class.new do
        include Mu::Action

        def call
          Failure("error", extra: "info")
        end
      end

      result = action_with_details.call

      expect(result.details).to eq(extra: "info")
      expect(result.meta).not_to have_key(:extra)
    end

    it "preserves metadata modifications made in hooks" do
      action_class.before { meta[:hook_data] = "added by hook" }
      action_class.after { meta[:completion_time] = Time.now }

      result = action_class.call(name: "Test")

      expect(result.meta).to include(
        hook_data: "added by hook",
        completion_time: be_a(Time)
      )
    end
  end

  describe "caller metadata" do
    it "does not modify the hash given by the caller" do
      given = { request_id: "abc" }
      instance = action_class.new(name: "Test", meta: given)

      expect(instance.meta).to include(request_id: "abc", class: action_class)
      expect(given).to eq(request_id: "abc")
    end
  end

  describe "record_props" do
    def recording(*args, **kwargs)
      Class.new do
        include Mu::Action

        prop :name, String
        prop :secret, String

        record_props(*args, **kwargs)

        def call = Success(:ok)
      end
    end

    it "records every prop by default" do
      expect(action_class.props_recording).to be true
    end

    it "records no props when disabled" do
      result = recording(false).call(name: "n", secret: "s")

      expect(result.meta).not_to have_key(:props)
    end

    it "records only the given props" do
      result = recording(only: :name).call(name: "n", secret: "s")

      expect(result.meta[:props]).to eq(name: "n")
    end

    it "records every prop except the given ones" do
      result = recording(except: %i[secret]).call(name: "n", secret: "s")

      expect(result.meta[:props]).to eq(name: "n")
    end

    it "is inherited without being shared" do
      parent = recording(except: %i[secret])
      child = Class.new(parent) { record_props false }

      expect(parent.props_recording).to eq(except: %i[secret])
      expect(child.props_recording).to be false
      expect(Class.new(parent).props_recording).to eq(except: %i[secret])
    end

    it "rejects only: with except:" do
      expect { recording(only: :name, except: :secret) }.to raise_error(ArgumentError, /not both/)
    end

    it "rejects false with only: or except:" do
      expect { recording(false, only: :name) }.to raise_error(ArgumentError, /accepts no only:/)
    end
  end

  describe "meta property" do
    it "adds meta property only once per class" do
      # Create multiple instances to trigger new method multiple times
      3.times { action_class.new(name: "Test#{_1}") }

      # Meta property should only be defined once
      meta_props = action_class.literal_properties.select { |p| p.name == :meta }
      expect(meta_props.size).to eq(1)
    end

    it "resets meta_prop_added flag for subclasses" do
      parent_class = Class.new do
        include Mu::Action

        prop :parent_prop, String
      end

      child_class = Class.new(parent_class) do
        prop :child_prop, String
      end

      # Both should have meta property
      parent_instance = parent_class.new(parent_prop: "parent")
      child_instance = child_class.new(parent_prop: "parent", child_prop: "child")

      expect(parent_instance.meta).to be_a(Hash)
      expect(child_instance.meta).to be_a(Hash)
      expect(child_instance.meta[:props]).to include(child_prop: "child")
    end
  end

  describe "complex property types" do
    let(:complex_action) do
      Class.new do
        include Mu::Action

        prop :config, Hash, default: -> { { setting: "default" } }
        prop :tags, Array, default: -> { [] }
        prop :timestamp, Time, default: -> { Time.now }

        def call
          Success("complex")
        end
      end
    end

    it "tracks complex property types in metadata" do
      now = Time.now
      instance = complex_action.new(
        config: { custom: "value" },
        tags: %w[tag1 tag2],
        timestamp: now
      )

      expect(instance.meta[:props]).to include(
        config: { custom: "value" },
        tags: %w[tag1 tag2],
        timestamp: now
      )
    end

    it "tracks default proc values" do
      instance = complex_action.new

      expect(instance.meta[:props][:config]).to eq({ setting: "default" })
      expect(instance.meta[:props][:tags]).to eq([])
      expect(instance.meta[:props][:timestamp]).to be_a(Time)
    end
  end

  describe "metadata immutability" do
    it "allows metadata modification during execution" do
      action_with_meta_changes = Class.new do
        include Mu::Action

        prop :name, String

        def call
          meta[:processed_at] = Time.now
          meta[:result_size] = @name.length
          Success("#{@name} processed")
        end
      end

      result = action_with_meta_changes.call(name: "TestName")

      expect(result.meta).to include(
        processed_at: be_a(Time),
        result_size: 8
      )
    end

    it "preserves original property values in metadata even if instance variables change" do
      instance = action_class.new(name: "Original")
      instance.meta.dup

      # Manually change instance variable (simulating internal modification)
      instance.instance_variable_set(:@name, "Modified")

      # Meta should still reflect original initialization values
      expect(instance.meta[:props][:name]).to eq("Original")
    end
  end
end
