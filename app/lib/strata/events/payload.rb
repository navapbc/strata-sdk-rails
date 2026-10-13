# frozen_string_literal: true

module Strata
  module Events
    # Payload converts event payloads to and from a JSON-compatible hash so events
    # can be stored and delivered later. It uses ActiveJob::Arguments, which keeps
    # symbol keys and stores records as GlobalID references.
    #
    # Payloads should contain identifiers, not record attributes or PII. serialize
    # raises if a payload contains anything other than scalars, timestamps, saved
    # records, or hashes and arrays of those. The check runs in every environment
    # because deserialize refuses anything else, so a payload that skipped it
    # would be stored but could never be delivered.
    #
    # GlobalIDs are only accepted for the current GlobalID.app, so renaming the
    # host application makes previously stored record references undeliverable.
    #
    # See docs/specs/durable-events/spec.md#payload-contract.
    #
    # @example
    #   data = Strata::Events::Payload.serialize({ case_id: kase.id })
    #   Strata::Events::Payload.deserialize(data) # => { case_id: "..." }
    #
    module Payload
      # Raised when a payload contains a value that is not an identifier,
      # timestamp, or saved record, or a hash key that is not a string or symbol.
      class InvalidPayloadError < ArgumentError; end

      # Raised when stored data names a serializer or GlobalID class that a
      # payload produced by serialize could not contain.
      class UnsafePayloadError < StandardError; end

      ALLOWED_SCALARS = [
        NilClass, TrueClass, FalseClass, String, Symbol, Integer, Float, BigDecimal,
        Date, Time, ActiveSupport::TimeWithZone
      ].freeze

      # The ActiveJob serializers that ALLOWED_SCALARS can produce.
      ALLOWED_SERIALIZERS = [
        ActiveJob::Serializers::SymbolSerializer,
        ActiveJob::Serializers::BigDecimalSerializer,
        ActiveJob::Serializers::DateSerializer,
        ActiveJob::Serializers::DateTimeSerializer,
        ActiveJob::Serializers::TimeSerializer,
        ActiveJob::Serializers::TimeWithZoneSerializer
      ].to_set(&:name).freeze

      # Keys that make ActiveJob deserialize a hash as something other than a Hash.
      VALUE_WRAPPER_KEYS = %w[_aj_globalid _aj_serialized].freeze

      class << self
        # @param [Hash] payload The event payload
        # @return [Hash] A JSON-compatible hash
        # @raise [InvalidPayloadError] for values that are not identifiers, timestamps, or saved records
        def serialize(payload)
          raise ArgumentError, "Event payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)

          validate_identifiers!(payload, [])
          ActiveJob::Arguments.serialize([ payload ]).first
        end

        # @param [Hash] data A hash returned by serialize, possibly after a JSON round trip
        # @return [Hash] The payload, with records loaded in their current state
        # @raise [UnsafePayloadError] if the data names a serializer or GlobalID that serialize could not produce
        # @raise [ActiveJob::DeserializationError] if a referenced record no longer exists
        # @raise [StandardError] the original error, unwrapped, if loading a record fails for another reason
        def deserialize(data)
          raise ArgumentError, "Event payload must be a Hash, got #{data.class}" unless data.is_a?(Hash)
          if VALUE_WRAPPER_KEYS.any? { |key| data.key?(key) }
            raise UnsafePayloadError, "Event payload must be a Hash at the top level, not a serialized value"
          end

          ensure_safe!(data)
          ActiveJob::Arguments.deserialize([ data ]).first
        rescue ActiveJob::DeserializationError => e
          # ActiveJob wraps every error in DeserializationError. Only a missing record is
          # permanent; anything else (such as a lost connection) may succeed on retry.
          raise if e.cause.nil? || e.cause.is_a?(ActiveRecord::RecordNotFound)

          raise e.cause
        end

        private

        def validate_identifiers!(value, path)
          case value
          when Hash
            value.each do |key, nested|
              validate_key!(key, path)
              validate_identifiers!(nested, [ *path, key ])
            end
          when Array
            value.each_with_index { |nested, index| validate_identifiers!(nested, [ *path, index ]) }
          when ActiveRecord::Base
            raise InvalidPayloadError, "Event payload record at #{path_label(path)} must be saved" unless value.persisted?
          when Float
            raise InvalidPayloadError, "Event payload value at #{path_label(path)} must be finite" unless value.finite?
          when *ALLOWED_SCALARS
            nil
          else
            raise InvalidPayloadError,
              "Event payload value at #{path_label(path)} is a #{value.class}; payloads may only contain " \
              "identifiers, timestamps, and saved records"
          end
        end

        def validate_key!(key, path)
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise InvalidPayloadError,
              "Event payload at #{path_label(path)} has key #{key.inspect}, a #{key.class}; keys must be strings or symbols"
          end
          return unless key.to_s.start_with?("_aj_")

          raise InvalidPayloadError, "Event payload at #{path_label(path)} has key #{key.inspect}, which ActiveJob reserves"
        end

        def path_label(path)
          path.empty? ? "top level" : path.join(".")
        end

        def ensure_safe!(value)
          case value
          when Hash
            ensure_allowed_serializer!(value["_aj_serialized"]) if value.key?("_aj_serialized")
            # ActiveJob only treats a hash as a GlobalID when that is its sole key.
            ensure_active_record_global_id!(value["_aj_globalid"]) if value.size == 1 && value.key?("_aj_globalid")
            value.each_value { |nested| ensure_safe!(nested) }
          when Array
            value.each { |nested| ensure_safe!(nested) }
          end
        end

        # ActiveJob constantizes the stored serializer name without checking that it is registered,
        # and some registered serializers (such as ModuleSerializer) constantize stored values.
        def ensure_allowed_serializer!(name)
          return if ALLOWED_SERIALIZERS.include?(name)

          raise UnsafePayloadError, "Event payload names disallowed serializer #{name.inspect}"
        end

        def ensure_active_record_global_id!(gid)
          parsed = GlobalID.parse(gid) if gid.is_a?(String)
          model_class = parsed&.model_name&.safe_constantize if parsed&.app == GlobalID.app
          return if model_class.is_a?(Class) && model_class < ActiveRecord::Base && !model_class.abstract_class?

          raise UnsafePayloadError, "Event payload GlobalID #{gid.inspect} is not an ActiveRecord model"
        end
      end
    end
  end
end
