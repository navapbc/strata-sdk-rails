# frozen_string_literal: true

module Strata
  module UserFacingId
    # Provides a keyed Feistel permutation over the 30-bit sequence domain.
    module Feistel
      DEFAULT_BITS = 30
      DEFAULT_ROUNDS = 6
      HALF_BITS = DEFAULT_BITS / 2
      HALF_MASK = (1 << HALF_BITS) - 1
      DOMAIN_SIZE = 1 << DEFAULT_BITS

      module_function

      def permute(value, key:, bits: DEFAULT_BITS, rounds: DEFAULT_ROUNDS)
        validate_key!(key)
        validate_domain!(value, bits)

        # Split the input into equal halves; each round swaps and mixes them.
        half_bits = bits / 2
        mask = (1 << half_bits) - 1
        left = value >> half_bits
        right = value & mask

        rounds.times do |round|
          left, right = right, left ^ round_function(right, round, key, mask)
        end

        (left << half_bits) | right
      end

      def invert(value, key:, bits: DEFAULT_BITS, rounds: DEFAULT_ROUNDS)
        validate_key!(key)
        validate_domain!(value, bits)

        # The inverse starts from the same split, then replays rounds backward.
        half_bits = bits / 2
        mask = (1 << half_bits) - 1
        left = value >> half_bits
        right = value & mask

        (rounds - 1).downto(0) do |round|
          left, right = right ^ round_function(left, round, key, mask), left
        end

        (left << half_bits) | right
      end

      def round_function(value, round, key, mask)
        # This is not cryptographic; it is just a deterministic keyed mixer.
        mixed = value ^ ((key >> (round % 16)) & mask)
        mixed = (mixed * 0x5bd1e995 + (round * 0x27d4eb2d) + key) & 0xffffffff
        mixed ^= mixed >> 15
        mixed ^= mixed >> 7
        mixed & mask
      end

      def validate_key!(key)
        return if key.is_a?(Integer) && key.positive?

        raise ArgumentError, "Feistel key must be a positive integer"
      end

      def validate_domain!(value, bits)
        raise ArgumentError, "Feistel domain must use an even bit count" unless bits.even?

        maximum = (1 << bits) - 1
        return if value.is_a?(Integer) && value.between?(0, maximum)

        raise RangeError, "value must be between 0 and #{maximum}"
      end
    end
  end
end
