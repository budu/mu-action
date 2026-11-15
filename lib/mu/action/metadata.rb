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
        # The names can be symbols or strings.
        def record_props(enabled = true, only: nil, except: nil) # rubocop:disable Style/OptionalBooleanParameter
          @props_recording = build_props_recording(enabled, only, except)
        end

        def props_recording = (defined?(@props_recording) ? @props_recording : true)

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

      # Initializes the metadata of each new action, and passes the props
      # recording of a class on to its subclasses.
      module Lifecycle
        # The metadata is initialized here and not in #initialize, because the
        # initializer that Literal generates for a subclass with its own props
        # does not call super.
        def new(...)
          instance = super
          instance.send(:initialize_meta)
          instance
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@props_recording, props_recording)
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
        in { only: } then props.slice(*only)
        in { except: } then props.except(*except)
        else props
        end
      end
    end
  end
end
