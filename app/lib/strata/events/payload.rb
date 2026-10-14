# frozen_string_literal: true

module Strata
  module Events
    # Payload converts event payloads to and from plain JSON so events can be
    # stored and delivered later.
    #
    # Payloads contain identifiers, not records, record attributes, or PII.
    # serialize raises unless a payload is a hash of strings, integers, finite
    # floats, booleans, nil, times, dates, and nested hashes and arrays of those.
    # Times are stored as ISO 8601 UTC strings and dates as ISO 8601 date
    # strings; both come back as strings.
    # deserialize returns the stored JSON with symbol keys; it never loads a
    # class or record named in stored data.
    #
    # See docs/specs/durable-events/spec.md#payload-contract.
    #
    # @example
    #   data = Strata::Events::Payload.serialize({ case_id: kase.id })
    #   Strata::Events::Payload.deserialize(data) # => { case_id: "..." }
    #
    module Payload
      # Raised when a payload contains a value or key that plain JSON cannot
      # store and return unchanged.
      class InvalidPayloadError < ArgumentError; end

      # Raised when stored payload data is not a hash, which means the stored
      # row is corrupt rather than that a publisher sent a bad payload.
      class CorruptPayloadError < StandardError; end

      class << self
        # @param [Hash] payload The event payload
        # @return [Hash] A hash with string keys, ready to store as JSON
        # @raise [InvalidPayloadError] for values or keys that would not survive a JSON round trip
        def serialize(payload)
          raise InvalidPayloadError, "Event payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)

          serialize_value(payload, [])
        end

        # @param [Hash] data A hash returned by serialize, after being stored as JSON
        # @return [Hash] The payload with symbol keys at every level
        # @raise [CorruptPayloadError] if the stored data is not a hash
        def deserialize(data)
          raise CorruptPayloadError, "Stored event payload must be a Hash, got #{data.class}" unless data.is_a?(Hash)

          data.deep_symbolize_keys
        end

        private

        def serialize_value(value, path)
          case value
          when Hash
            serialize_hash(value, path)
          when Array
            value.each_with_index.map { |nested, index| serialize_value(nested, [ *path, index ]) }
          when nil, true, false, Integer
            value
          when Float
            raise InvalidPayloadError, "Event payload value at #{path_label(path)} must be finite" unless value.finite?

            value
          when String
            json_string(value) || raise(InvalidPayloadError,
              "Event payload string at #{path_label(path)} must be valid UTF-8 without NUL bytes")
          when ActiveSupport::TimeWithZone, Time, DateTime
            # Normalize to UTC so equal instants always store identical strings.
            value.to_time.utc.iso8601(6)
          when Date
            value.iso8601
          when BigDecimal
            raise InvalidPayloadError,
              "Event payload value at #{path_label(path)} is a BigDecimal, which JSON cannot store exactly; " \
              "publish integer cents or a string instead"
          when ActiveRecord::Base
            raise InvalidPayloadError,
              "Event payload value at #{path_label(path)} is a #{value.class} record; publish its id instead"
          else
            raise InvalidPayloadError,
              "Event payload value at #{path_label(path)} is a #{value.class}; payloads may only contain " \
              "strings, numbers, booleans, nil, times, dates, hashes, and arrays"
          end
        end

        def serialize_hash(hash, path)
          hash.each_with_object({}) do |(key, nested), result|
            string_key = serialize_key(key, path)
            if result.key?(string_key)
              raise InvalidPayloadError, "Event payload at #{path_label(path)} has duplicate key #{string_key.inspect}"
            end

            result[string_key] = serialize_value(nested, [ *path, string_key ])
          end
        end

        def serialize_key(key, path)
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise InvalidPayloadError,
              "Event payload at #{path_label(path)} has a #{key.class} key; keys must be strings or symbols"
          end

          json_string(key.to_s) || raise(InvalidPayloadError,
            "Event payload at #{path_label(path)} has a key that is not valid UTF-8 or contains a NUL byte")
        end

        # Returns the string as UTF-8, or nil if JSON or Postgres jsonb cannot store it.
        def json_string(string)
          utf8 = string.encode(Encoding::UTF_8)
          utf8 if utf8.valid_encoding? && !utf8.include?("\u0000")
        rescue EncodingError
          nil
        end

        def path_label(path)
          path.empty? ? "top level" : path.join(".")
        end
      end
    end
  end
end
