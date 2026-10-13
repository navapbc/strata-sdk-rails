# frozen_string_literal: true

module Strata
  module Events
    # Payload converts event payloads to and from a JSON-compatible hash so events
    # can be stored and delivered later. It uses ActiveJob::Arguments, which keeps
    # symbol keys and stores records as GlobalID references.
    #
    # Payloads should contain identifiers, not record attributes or PII. In
    # development and test, serialize raises if a payload contains anything other
    # than scalars, timestamps, saved records, or hashes and arrays of those.
    # Production skips that check so it cannot reject a person's submission.
    #
    # See docs/specs/durable-events/spec.md#payload-contract.
    #
    # @example
    #   data = Strata::Events::Payload.serialize({ case_id: kase.id })
    #   Strata::Events::Payload.deserialize(data) # => { case_id: "..." }
    #
    module Payload
      # Raised in development and test when a payload contains a value that is not
      # an identifier, timestamp, or saved record.
      class InvalidPayloadError < ArgumentError; end

      # Raised when stored data names a serializer or GlobalID class that a
      # payload produced by serialize could not contain.
      class UnsafePayloadError < StandardError; end

      ALLOWED_SCALARS = [
        NilClass, TrueClass, FalseClass, String, Symbol, Integer, Float, BigDecimal,
        Date, Time, ActiveSupport::TimeWithZone
      ].freeze

      class << self
        # @param [Hash] payload The event payload
        # @return [Hash] A JSON-compatible hash
        # @raise [InvalidPayloadError] in development and test, for values that are not identifiers
        # @raise [ActiveJob::SerializationError] for values ActiveJob cannot serialize
        def serialize(payload)
          raise ArgumentError, "Event payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)

          validate_identifiers!(payload, []) if Rails.env.local?
          ActiveJob::Arguments.serialize([ payload ]).first
        end

        # @param [Hash] data A hash returned by serialize, possibly after a JSON round trip
        # @return [Hash] The payload, with records loaded in their current state
        # @raise [UnsafePayloadError] if the data names an unregistered serializer or a non-ActiveRecord GlobalID
        # @raise [ActiveJob::DeserializationError] if a referenced record no longer exists
        def deserialize(data)
          ensure_safe!(data)
          ActiveJob::Arguments.deserialize([ data ]).first
        end

        private

        def validate_identifiers!(value, path)
          case value
          when Hash
            value.each { |key, nested| validate_identifiers!(nested, [ *path, key ]) }
          when Array
            value.each_with_index { |nested, index| validate_identifiers!(nested, [ *path, index ]) }
          when ActiveRecord::Base
            raise InvalidPayloadError, "Event payload record at #{path.join('.')} must be saved" unless value.persisted?
          when *ALLOWED_SCALARS
            nil
          else
            raise InvalidPayloadError,
              "Event payload value at #{path.join('.')} is a #{value.class}; payloads may only contain " \
              "identifiers, timestamps, and saved records"
          end
        end

        def ensure_safe!(value)
          case value
          when Hash
            ensure_registered_serializer!(value["_aj_serialized"]) if value.key?("_aj_serialized")
            ensure_active_record_global_id!(value["_aj_globalid"]) if value.key?("_aj_globalid")
            value.each_value { |nested| ensure_safe!(nested) }
          when Array
            value.each { |nested| ensure_safe!(nested) }
          end
        end

        # ActiveJob constantizes the stored serializer name without checking that it is registered.
        def ensure_registered_serializer!(name)
          return if ActiveJob::Serializers.serializers.any? { |serializer| serializer.name == name }

          raise UnsafePayloadError, "Event payload names unregistered serializer #{name.inspect}"
        end

        def ensure_active_record_global_id!(gid)
          model_class = GlobalID.parse(gid)&.model_name&.safe_constantize
          return if model_class.is_a?(Class) && model_class < ActiveRecord::Base

          raise UnsafePayloadError, "Event payload GlobalID #{gid.inspect} is not an ActiveRecord model"
        end
      end
    end
  end
end
