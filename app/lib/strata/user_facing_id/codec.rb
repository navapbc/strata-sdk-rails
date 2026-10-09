# frozen_string_literal: true

module Strata
  module UserFacingId
    # Encodes sequence integers into user-facing IDs and decodes them back.
    #
    # Intended as attribute-internal: callers should go through
    # `user_facing_id_attribute` rather than invoking the codec directly.
    # In particular, alphabet inputs are validated by the attribute layer,
    # not here — calling Codec.encode/decode with a malformed alphabet
    # (empty, duplicates, non-letters) is undefined.
    module Codec
      SEGMENT_COUNT = 3

      # Total formatted space before reserving four low bits for parity.
      ENCODED_CAPACITY = Alphabet::BASE**SEGMENT_COUNT
      DATA_CAPACITY = ENCODED_CAPACITY / 16
      MAX_VALUE = DATA_CAPACITY - 1

      module_function

      def encode(value, prefix:, key:, alphabet: Alphabet::DEFAULT)
        integer = normalize_integer(value)
        base = alphabet.length * Alphabet::DIGITS_PER_LETTER
        capacity = data_capacity(base)
        validate_capacity!(integer, capacity)

        data_value = cycle_walk_encode(integer, key: key, capacity: capacity)

        # Store parity in the low four bits before splitting into LNN segments.
        packed_value = Parity.append(data_value, base: base)
        segments = encode_segments(packed_value, alphabet: alphabet, base: base)

        ([ normalize_prefix(prefix) ] + segments).join("-")
      end

      def decode(value, prefix:, key:, alphabet: Alphabet::DEFAULT)
        base = alphabet.length * Alphabet::DIGITS_PER_LETTER
        capacity = data_capacity(base)
        packed_value = decode_segments(value, prefix: prefix, alphabet: alphabet, base: base)
        data_value, parity = Parity.split(packed_value)

        # Encode-time over-capacity is a programmer error (RangeError, raised by
        # validate_capacity!), but decode-time over-capacity means the input is
        # not a valid ID we could have issued — raise FormatError so callers and
        # the attribute's permissive query path treat it like any other malformed
        # input rather than leaking a standard-library RangeError.
        unless data_value.between?(0, capacity - 1)
          raise FormatError, "user-facing ID data value is outside the encodable range"
        end

        Parity.validate!(data_value, parity, base: base)

        cycle_walk_decode(data_value, key: key, capacity: capacity)
      end

      def normalize_prefix(prefix)
        normalized = prefix.to_s.strip.upcase
        return normalized if normalized.match?(/\A[A-Z0-9]+\z/)

        raise FormatError, "user-facing ID prefix must contain only letters and numbers"
      end

      def encode_segments(value, alphabet: Alphabet::DEFAULT, base: Alphabet::BASE)
        # Build right-to-left from the least-significant chunk, then unshift so the
        # most-significant segment appears first in the rendered ID.
        remaining = value
        segments = []
        SEGMENT_COUNT.times do
          remaining, chunk = remaining.divmod(base)
          segments.unshift(Alphabet.encode(chunk, alphabet: alphabet))
        end
        segments
      end

      def decode_segments(value, prefix:, alphabet: Alphabet::DEFAULT, base: Alphabet::BASE)
        expected_prefix = normalize_prefix(prefix)
        parts = value.to_s.strip.upcase.split("-")
        raise FormatError, "invalid user-facing ID format" unless parts.length == SEGMENT_COUNT + 1
        raise FormatError, "invalid user-facing ID prefix" unless parts.first == expected_prefix

        parts.drop(1).reduce(0) do |memo, segment|
          (memo * base) + Alphabet.decode(segment, alphabet: alphabet)
        end
      end

      def normalize_integer(value)
        Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, "user-facing ID source value must be an integer"
      end

      # Effective per-alphabet data capacity. With smaller alphabets the segment
      # space is the binding limit; with a full 26-letter alphabet, BASE^3/16
      # exceeds Feistel's 30-bit domain so the Feistel ceiling binds instead.
      def data_capacity(base)
        [ base**SEGMENT_COUNT / 16, Feistel::DOMAIN_SIZE ].min
      end

      def validate_capacity!(value, capacity)
        return if value.between?(0, capacity - 1)

        raise RangeError, "user-facing ID source value must be between 0 and #{capacity - 1}"
      end

      def cycle_walk_encode(value, key:, capacity: DATA_CAPACITY)
        current = value

        # Feistel permutes a power-of-two domain; cycle-walk until it lands in
        # the smaller displayable data domain.
        loop do
          current = Feistel.permute(current, key: key)
          return current if current < capacity
        end
      end

      def cycle_walk_decode(value, key:, capacity: DATA_CAPACITY)
        current = value

        # Decoding mirrors the same cycle walk using the inverse permutation.
        loop do
          current = Feistel.invert(current, key: key)
          return current if current < capacity
        end
      end
    end
  end
end
