# frozen_string_literal: true

module Mu
  module Action
    # The metadata of an action: diagnostic information such as its class and
    # the values of its props, carried over to its result.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Metadata
      # The instance variable of an action class that holds its own choice of
      # the props to record.
      RECORDING = :@mu_action_props_recording

      def self.install(base)
        base.extend(ClassMethods)
        base.singleton_class.prepend(Lifecycle)
        # The coercion copies the hash, so that one given by the caller is
        # never modified.
        base.prop(:meta, Hash, default: -> { {} }, &:dup) # steep:ignore UnannotatedEmptyCollection
      end

      # The props of an action to record in its metadata, by name, or nil when
      # the action records none.
      def self.recorded_props(action)
        recording = recording(action.class)
        return if recording == false

        props = action.class.literal_properties.to_h do |prop|
          [prop.name, action.instance_variable_get(:"@#{prop.name}")] #: [Symbol, untyped]
        end.except(:meta, :context)

        case recording
        in { only: } then props.slice(*known_props(action, only, props))
        in { except: } then props.except(*known_props(action, except, props))
        else props
        end
      end

      # Records the choice of an action class: every prop, none, or a subset.
      def self.record(action_class, enabled, only, except)
        action_class.instance_variable_set(RECORDING, build_recording(enabled, only, except))
        nil
      end

      # Class methods that choose which props are recorded in the metadata.
      #
      # @api public
      module ClassMethods
        # Chooses which props are recorded in meta[:props]: all of them (the
        # default), none, or a subset.
        #
        #   record_props false
        #   record_props only: %i[site_id]
        #   record_props except: %i[payload]
        #
        # The names can be symbols or strings. Each one must be a prop of the
        # action, and of every subclass that inherits the choice: this is checked
        # when an action is instantiated, since props can be declared afterwards.
        def record_props(enabled = true, only: nil, except: nil) # rubocop:disable Style/OptionalBooleanParameter
          Metadata.record(self, enabled, only, except)
        end
      end

      # Initializes the metadata of each new action.
      module Lifecycle
        # The metadata is initialized here and not in #initialize, because the
        # initializer that Literal generates for a subclass with its own props
        # does not call super.
        def new(...)
          instance = super
          instance.send(:initialize_meta)
          instance
        end
      end

      class << self
        private

        # The choice of an action class, or else the one of its parent class.
        # It is worked out when read, so that a choice made on a parent class
        # reaches its subclasses whenever it is made.
        def recording(action_class)
          return action_class.instance_variable_get(RECORDING) if action_class.instance_variable_defined?(RECORDING)

          parent = Action.parent(action_class)
          parent ? recording(parent) : true
        end

        def build_recording(enabled, only, except)
          unless [true, false].include?(enabled)
            raise ArgumentError, "record_props takes true or false, got #{enabled.inspect}: " \
                                 "name the props with only: or except:"
          end
          raise ArgumentError, "record_props accepts only: or except:, not both" if only && except

          # @type var filter: ::Hash[Symbol, ::Array[Symbol]]
          filter = { only:, except: }.compact.transform_values { symbolize(_1) }
          return filter.empty? || filter if enabled
          raise ArgumentError, "record_props false accepts no only: or except:" if filter.any?

          false
        end

        def symbolize(names)
          # @type var list: ::Array[untyped]
          list = Array(names)
          list.map(&:to_sym)
        end

        # The names, once each of them is known to be a prop. A name that
        # matches no prop would otherwise be ignored, and a misspelled name in
        # except: would leave the prop it meant to exclude recorded.
        def known_props(action, names, props)
          unknown = names - props.keys
          return names if unknown.empty?

          raise ArgumentError, "#{action.class}: record_props names props that do not exist: #{unknown.inspect}"
        end
      end
    end
  end
end
