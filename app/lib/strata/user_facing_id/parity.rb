# frozen_string_literal: true

module Strata
  module UserFacingId
    # Calculates and validates the 4-bit checksum embedded in user-facing IDs.
    module Parity
      # Different weights spread the parity across the three segment chunks so that
      # a single-segment (one-letter or one-two-digit) typo is caught with high
      # probability; random tampering passes the check at ~1/16.
      WEIGHTS = [ 1, 3, 7 ].freeze

      # Four parity bits can represent checksums from 0 through 15.
      MASK = 0b1111

      module_function

      def calculate(value, base: Alphabet::BASE)
        # Work in the same base as the visible LNN segments so that custom-alphabet
        # IDs get chunked the same way the codec splits them on decode.
        chunks = [
          value % base,
          (value / base) % base,
          (value / (base**2)) % base
        ]

        chunks.zip(WEIGHTS).sum { |chunk, weight| chunk * weight } % 16
      end

      def append(value, base: Alphabet::BASE)
        # Shift data left, then use the low four bits for the checksum.
        (value << 4) | calculate(value, base: base)
      end

      def split(value)
        # Undo append: data lives above the low four parity bits.
        [ value >> 4, value & MASK ]
      end

      def valid?(value, parity, base: Alphabet::BASE)
        calculate(value, base: base) == parity
      end

      def validate!(value, parity, base: Alphabet::BASE)
        return true if valid?(value, parity, base: base)

        raise ParityError, "invalid user-facing ID parity"
      end
    end
  end
end
