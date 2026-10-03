# frozen_string_literal: true

module Strata
  module Attributes
    # Adds a derived user-facing ID attribute backed by an integer sequence column.
    module UserFacingIdAttribute
      extend ActiveSupport::Concern

      def self.attribute_type
        :derived_single_column
      end

      # Casts formatted user-facing IDs to their backing integer sequence values.
      class UserFacingIdSequenceType < ActiveModel::Type::Integer
        def initialize(prefix:, key:, alphabet:)
          @prefix = prefix
          @key = key
          @alphabet = alphabet
          super()
        end

        # Permissive on the query path: malformed input from `where(...)` /
        # `find_by(...)` should produce an empty result, not raise. Rails calls
        # cast on the predicate builder side too, so this can't be loud without
        # breaking query semantics — the loud behavior lives on the per-attribute
        # sequence-column setter defined below.
        def cast(value)
          return nil if value.nil?
          return value if value.is_a?(Integer)

          Strata::UserFacingId::Codec.decode(value, prefix: @prefix, key: @key, alphabet: @alphabet)
        rescue Strata::UserFacingId::Error
          nil
        end

        # Route serialize through cast so query strings like "T-Y01-B33-N91" are decoded
        # to the integer sequence; the inherited Integer#serialize would coerce them to 0.
        def serialize(value)
          cast(value)
        end
      end

      class_methods do
        def user_facing_id_attribute(name, options = {})
          prefix = options.fetch(:prefix)
          sequence_column = options.fetch(:sequence_column, :"#{name}_sequence")
          key = options.fetch(:key)
          alphabet = options.fetch(:alphabet, Strata::UserFacingId::Alphabet::DEFAULT)

          Strata::UserFacingId::Codec.normalize_prefix(prefix)
          alphabet = Strata::Attributes::UserFacingIdAttribute.validate_alphabet!(alphabet)

          attribute sequence_column, UserFacingIdSequenceType.new(prefix: prefix, key: key, alphabet: alphabet)
          alias_attribute name, sequence_column

          define_method(name) do
            sequence_value = public_send(sequence_column)
            next nil if sequence_value.nil?

            Strata::UserFacingId::Codec.encode(sequence_value, prefix: prefix, key: key, alphabet: alphabet)
          end

          # Raise on bad string assignment (loud, debuggable) while leaving the
          # type's permissive cast in place so query paths still return nil.
          define_method("#{name}=") do |value|
            coerced =
              if value.is_a?(String) && value.strip.present?
                Strata::UserFacingId::Codec.decode(value, prefix: prefix, key: key, alphabet: alphabet)
              else
                value
              end

            public_send("#{sequence_column}=", coerced)
          end

          # The column's permissive cast (needed for query semantics) would
          # silently nil any string that fails to decode, including innocuous
          # integer-as-string assignments. Override the sequence-column setter
          # to raise loudly so misuse surfaces at the call site rather than
          # turning into a NULL write.
          define_method("#{sequence_column}=") do |value|
            coerced =
              if value.is_a?(String) && value.strip.present?
                Strata::UserFacingId::Codec.decode(value, prefix: prefix, key: key, alphabet: alphabet)
              else
                value
              end

            write_attribute(sequence_column, coerced)
          end
        end
      end

      # 26 is the Feistel ceiling: any larger and capacity exceeds the 2^30 permutation
      # domain, so values near the top of BASE^3/16 become unreachable.
      MAX_ALPHABET_LENGTH = 26

      def self.validate_alphabet!(alphabet)
        unless alphabet.is_a?(Array)
          raise Strata::UserFacingId::FormatError, "user-facing ID alphabet must be an Array"
        end
        if alphabet.empty?
          raise Strata::UserFacingId::FormatError, "user-facing ID alphabet must not be empty"
        end
        if alphabet.length > MAX_ALPHABET_LENGTH
          raise Strata::UserFacingId::FormatError,
            "user-facing ID alphabet must contain at most #{MAX_ALPHABET_LENGTH} letters"
        end
        unless alphabet.all? { |letter| letter.is_a?(String) && letter.match?(/\A[A-Z]\z/) }
          raise Strata::UserFacingId::FormatError,
            "user-facing ID alphabet entries must be single uppercase letters A-Z"
        end
        if alphabet.uniq.length != alphabet.length
          raise Strata::UserFacingId::FormatError, "user-facing ID alphabet must not contain duplicates"
        end

        # Dup-and-freeze so the alphabet captured by the attribute is immutable;
        # callers may keep mutating their original array without affecting
        # already-issued IDs.
        alphabet.dup.freeze
      end
    end
  end
end
