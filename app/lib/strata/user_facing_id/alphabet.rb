# frozen_string_literal: true

module Strata
  module UserFacingId
    # Encodes and decodes one LNN segment using the default user-facing alphabet.
    module Alphabet
      # "I" is skipped to avoid confusion with "1" in printed or spoken IDs.
      DEFAULT = (("A".."Z").to_a - [ "I" ]).freeze

      # Each segment is one letter plus two digits, so each letter owns 00-99.
      DIGITS_PER_LETTER = 100

      # With the default alphabet, each segment can encode 25 * 100 values.
      BASE = DEFAULT.length * DIGITS_PER_LETTER

      module_function

      def encode(value, alphabet: DEFAULT)
        validate_value!(value, alphabet)

        letter = alphabet[value / DIGITS_PER_LETTER]
        number = value % DIGITS_PER_LETTER

        "#{letter}#{number.to_s.rjust(2, "0")}"
      end

      def decode(segment, alphabet: DEFAULT)
        match = segment.to_s.upcase.match(/\A([A-Z])(\d{2})\z/)
        raise FormatError, "invalid user-facing ID segment" unless match

        # Reject letters that match the shape but are not in the configured alphabet.
        letter_index = alphabet.index(match[1])
        raise FormatError, "invalid user-facing ID segment" unless letter_index

        (letter_index * DIGITS_PER_LETTER) + match[2].to_i
      end

      def validate_value!(value, alphabet)
        maximum = (alphabet.length * DIGITS_PER_LETTER) - 1
        return if value.is_a?(Integer) && value.between?(0, maximum)

        raise RangeError, "segment value must be between 0 and #{maximum}"
      end
    end
  end
end
