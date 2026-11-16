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

    it "declares the meta prop when Mu::Action is included" do
      expect(action_class.literal_properties.map(&:name)).to include(:meta)
    end

    it "does not change the class when it is instantiated" do
      initializer = action_class.instance_method(:initialize)
      props = action_class.literal_properties.map(&:name)

      action_class.new(name: "Test")

      expect(action_class.instance_method(:initialize)).to eq(initializer)
      expect(action_class.literal_properties.map(&:name)).to eq(props)
    end

    it "initializes the metadata once, for a class and for its subclasses" do
      calls = []
      counting = Class.new do
        include Mu::Action

        prop :name, String

        define_method(:initialize_meta) do
          calls << self.class
          super()
        end
        private :initialize_meta
      end
      with_prop = Class.new(counting) { prop :extra, Integer, default: 1 }
      without_prop = Class.new(counting)

      [counting, with_prop, without_prop].each { _1.new(name: "Test") }

      expect(calls).to eq([counting, with_prop, without_prop])
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

    it "keeps the values the props had when the action was built" do
      changing = Class.new(action_class) do
        def call
          @name = "Modified"
          Success(@name)
        end
      end

      result = changing.call(name: "Original")

      expect(result.value).to eq("Modified")
      expect(result.meta[:props]).to include(name: "Original")
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

    it "does not modify it from after_initialize either" do
      marking = Class.new(action_class) do
        private

        def after_initialize = meta[:seen] = true
      end
      given = { request_id: "abc" }
      instance = marking.new(name: "Test", meta: given)

      expect(instance.meta).to include(request_id: "abc", seen: true)
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

    it "accepts prop names given as strings" do
      excluding = recording(except: %w[secret]).call(name: "n", secret: "s")
      keeping = recording(only: "name").call(name: "n", secret: "s")

      expect(excluding.meta[:props]).to eq(name: "n")
      expect(keeping.meta[:props]).to eq(name: "n")
    end

    it "rejects a first argument that is not true or false" do
      expect { recording(:name) }
        .to raise_error(ArgumentError, /takes true or false, got :name: name the props with only: or except:/)
      expect { recording(nil) }.to raise_error(ArgumentError, /takes true or false, got nil/)
    end

    it "rejects a name that is not a prop, when the action is instantiated" do
      misspelled = recording(except: %i[secrte])

      expect { misspelled.call(name: "n", secret: "s") }
        .to raise_error(ArgumentError, /record_props names props that do not exist: \[:secrte\]/)
      expect { recording(only: %i[name nmae]).new(name: "n", secret: "s") }
        .to raise_error(ArgumentError, /do not exist: \[:nmae\]/)
    end

    it "accepts the name of a prop declared after record_props" do
      late = Class.new do
        include Mu::Action

        record_props except: :token
        prop :token, String

        def call = Success(:ok)
      end

      expect(late.call(token: "t").meta[:props]).to eq({})
    end

    it "checks the names against the props of each class that inherits them" do
      parent = Class.new do
        include Mu::Action

        record_props except: :token

        def call = Success(:ok)
      end
      child = Class.new(parent) { prop :token, String }

      expect(child.call(token: "t").meta[:props]).to eq({})
      expect { parent.call }.to raise_error(ArgumentError, /do not exist: \[:token\]/)
    end

    it "records every prop when given true" do
      expect(recording(true).call(name: "n", secret: "s").meta[:props]).to eq(name: "n", secret: "s")
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

    it "gives subclasses the meta property" do
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
  end
end
