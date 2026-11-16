# frozen_string_literal: true

module Mu
  module Action
    # The metadata of an action: diagnostic information such as its class and
    # the values of its props, carried over to its result.
    #
    # @api private Applications use what this module adds to action classes,
    #   never the module itself.
    module Metadata
      def self.included(base)
        base.extend(ClassMethods)
        base.singleton_class.prepend(Lifecycle)
        # The coercion copies the hash, so that one given by the caller is
        # never modified.
        base.prop(:meta, Hash, default: -> { {} }, &:dup) # steep:ignore UnannotatedEmptyCollection
        base.attr_reader :meta
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
          @props_recording = build_props_recording(enabled, only, except)
        end

        # The choice of this class, or else the one of its parent class. It is
        # worked out when read, so that a choice made on a parent class reaches
        # its subclasses whenever it is made.
        def props_recording
          return @props_recording if defined?(@props_recording)

          # @type var parent: untyped
          parent = superclass
          parent.respond_to?(:props_recording) ? parent.props_recording : true
        end

        private

        def build_props_recording(enabled, only, except)
          unless [true, false].include?(enabled)
            raise ArgumentError, "record_props takes true or false, got #{enabled.inspect}: " \
                                 "name the props with only: or except:"
          end
          raise ArgumentError, "record_props accepts only: or except:, not both" if only && except

          # @type var filter: ::Hash[Symbol, ::Array[Symbol]]
          filter = { only:, except: }.compact.transform_values { symbolize_prop_names(_1) }
          return filter.empty? || filter if enabled
          raise ArgumentError, "record_props false accepts no only: or except:" if filter.any?

          false
        end

        def symbolize_prop_names(names)
          # @type var list: ::Array[untyped]
          list = Array(names)
          list.map(&:to_sym)
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

      private

      def initialize_meta
        meta[:class] = self.class
        props = recorded_props
        meta[:props] = props if props
        meta[:context] = context unless context.nil?
      end

      def recorded_props
        recording = self.class.props_recording
        return if recording == false

        props = self.class.literal_properties.to_h do |prop|
          [prop.name, instance_variable_get(:"@#{prop.name}")] #: [Symbol, untyped]
        end.except(:meta, :context)

        case recording
        in { only: } then props.slice(*known_props(only, props))
        in { except: } then props.except(*known_props(except, props))
        else props
        end
      end

      # The names, once each of them is known to be a prop. A name that matches
      # no prop would otherwise be ignored, and a misspelled name in except:
      # would leave the prop it meant to exclude recorded.
      def known_props(names, props)
        unknown = names - props.keys
        return names if unknown.empty?

        raise ArgumentError, "#{self.class}: record_props names props that do not exist: #{unknown.inspect}"
      end
    end
  end
end
