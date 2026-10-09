# frozen_string_literal: true

require "rails_helper"

# Locked encodings: future changes to Feistel rounds, parity weights, or the
# alphabet must update this table deliberately — any change here breaks every
# issued ID downstream. Defined outside the example group so they can drive
# example generation in `each` loops below.
custom_key = 0xdead_beef
test_key = 0x5a3c_9e21
max_value = Strata::UserFacingId::Codec::MAX_VALUE

golden_cases = [
  { prefix: "T",     key: test_key,   sequence: 0,         encoded: "T-C24-T46-Y51" },
  { prefix: "T",     key: test_key,   sequence: 1,         encoded: "T-Y55-F21-A99" },
  { prefix: "T",     key: test_key,   sequence: 2,         encoded: "T-K82-T85-H69" },
  { prefix: "T",     key: test_key,   sequence: 100,       encoded: "T-N26-F54-X99" },
  { prefix: "T",     key: test_key,   sequence: 12_345,    encoded: "T-V64-Z59-H64" },
  { prefix: "T",     key: test_key,   sequence: 1_000_000, encoded: "T-F55-B74-Z10" },
  { prefix: "T",     key: test_key,   sequence: max_value, encoded: "T-G86-E57-P40" },
  { prefix: "CLAIM", key: test_key,   sequence: 0,         encoded: "CLAIM-C24-T46-Y51" },
  { prefix: "CLAIM", key: test_key,   sequence: 1,         encoded: "CLAIM-Y55-F21-A99" },
  { prefix: "CLAIM", key: test_key,   sequence: 12_345,    encoded: "CLAIM-V64-Z59-H64" },
  { prefix: "T",     key: custom_key, sequence: 0,         encoded: "T-N41-W82-Q18" },
  { prefix: "T",     key: custom_key, sequence: 1,         encoded: "T-H80-Z47-J66" },
  { prefix: "T",     key: custom_key, sequence: 12_345,    encoded: "T-P03-O83-R39" }
].freeze

RSpec.describe Strata::UserFacingId::Codec do
  let(:custom_key) { 0xdead_beef }
  let(:test_key) { 0x5a3c_9e21 }

  describe "constants" do
    it "locks the segment count and capacity" do
      # These values define the encoding contract: changing any of them would
      # invalidate every previously issued user-facing ID.
      expect(described_class::SEGMENT_COUNT).to eq(3)
      expect(described_class::ENCODED_CAPACITY).to eq(15_625_000_000)
      expect(described_class::DATA_CAPACITY).to eq(976_562_500)
      expect(described_class::MAX_VALUE).to eq(976_562_499)
    end
  end

  describe "golden table" do
    golden_cases.each do |case_data|
      label = "prefix=#{case_data[:prefix]} key=0x#{case_data[:key].to_s(16)} sequence=#{case_data[:sequence]}"

      it "encodes #{label} to #{case_data[:encoded]}" do
        expect(described_class.encode(case_data[:sequence], prefix: case_data[:prefix], key: case_data[:key]))
          .to eq(case_data[:encoded])
      end

      it "decodes #{case_data[:encoded]} back to sequence #{case_data[:sequence]}" do
        expect(described_class.decode(case_data[:encoded], prefix: case_data[:prefix], key: case_data[:key]))
          .to eq(case_data[:sequence])
      end
    end
  end

  describe "required arguments" do
    it "raises ArgumentError when :key is omitted from encode" do
      expect { described_class.encode(12_345, prefix: "T") }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError when :key is omitted from decode" do
      expect { described_class.decode("T-V64-Z59-H64", prefix: "T") }.to raise_error(ArgumentError)
    end
  end

  describe ".encode and .decode" do
    it "round-trips a representative set of sequence values" do
      [
        0,
        1,
        12_345,
        1_000_000,
        described_class::MAX_VALUE
      ].each do |value|
        encoded = described_class.encode(value, prefix: "C", key: test_key)

        expect(described_class.decode(encoded, prefix: "C", key: test_key)).to eq(value)
      end
    end

    it "uses a three-segment user-facing format" do
      encoded = described_class.encode(12_345, prefix: "C", key: test_key)

      expect(encoded).to match(/\AC-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}\z/)
    end

    it "is deterministic" do
      encoded = described_class.encode(12_345, prefix: "C", key: test_key)

      expect(described_class.encode(12_345, prefix: "C", key: test_key)).to eq(encoded)
    end

    it "produces encoded strings of constant length for any value" do
      lengths = (0...10_000).map { |value| described_class.encode(value, prefix: "T", key: test_key).length }

      expect(lengths.uniq).to eq([ "T-A00-A00-A00".length ])
    end

    it "round-trips every value across a 50,000-value sweep" do
      (0...50_000).each do |value|
        encoded = described_class.encode(value, prefix: "T", key: test_key)
        expect(described_class.decode(encoded, prefix: "T", key: test_key)).to eq(value)
      end
    end

    it "does not collide across a sample of the domain" do
      encoded_values = (0...50_000).map { |value| described_class.encode(value, prefix: "C", key: test_key) }

      expect(encoded_values.uniq.size).to eq(encoded_values.size)
    end

    it "round-trips boundary values exactly" do
      [ 0, described_class::MAX_VALUE ].each do |value|
        encoded = described_class.encode(value, prefix: "T", key: test_key)

        expect(described_class.decode(encoded, prefix: "T", key: test_key)).to eq(value)
      end
    end

    it "accepts lowercase formatted IDs on decode" do
      encoded = described_class.encode(12_345, prefix: "T", key: test_key)

      expect(described_class.decode(encoded.downcase, prefix: "T", key: test_key)).to eq(12_345)
    end

    it "accepts leading and trailing whitespace on decode" do
      encoded = described_class.encode(12_345, prefix: "T", key: test_key)

      expect(described_class.decode("  #{encoded}  ", prefix: "T", key: test_key)).to eq(12_345)
    end

    it "raises for invalid format" do
      expect do
        described_class.decode("C-Y01-I33-N91", prefix: "C", key: test_key)
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises for a prefix mismatch" do
      encoded = described_class.encode(12_345, prefix: "C", key: test_key)

      expect do
        described_class.decode(encoded, prefix: "D", key: test_key)
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises for a parity mismatch" do
      encoded = described_class.encode(12_345, prefix: "C", key: test_key)
      tampered = encoded.sub(/\d\z/) { |digit| ((digit.to_i + 1) % 10).to_s }

      expect do
        described_class.decode(tampered, prefix: "C", key: test_key)
      end.to raise_error(Strata::UserFacingId::ParityError)
    end

    it "raises when the value is outside the available capacity" do
      expect do
        described_class.encode(described_class::MAX_VALUE + 1, prefix: "C", key: test_key)
      end.to raise_error(RangeError)
    end
  end

  describe "key isolation" do
    it "produces different encoded strings for the same sequence under different keys" do
      first_encoded = described_class.encode(12_345, prefix: "T", key: test_key)
      custom_encoded = described_class.encode(12_345, prefix: "T", key: custom_key)

      expect(first_encoded).not_to eq(custom_encoded)
    end

    it "round-trips losslessly under any key" do
      [ 0, 1, 12_345, 1_000_000, described_class::MAX_VALUE ].each do |value|
        encoded = described_class.encode(value, prefix: "T", key: custom_key)

        expect(described_class.decode(encoded, prefix: "T", key: custom_key)).to eq(value)
      end
    end

    it "never recovers the original sequence when decoded with the wrong key" do
      # Decoding with the wrong key either raises (parity mismatch) or recovers
      # a *different* integer. It must never silently return the original value;
      # callers that need authentication must rotate keys, not rely on parity.
      sequences = [ 0, 1, 12_345, 1_000_000, described_class::MAX_VALUE ]
      recovered_count = 0

      sequences.each do |value|
        encoded = described_class.encode(value, prefix: "T", key: test_key)
        begin
          decoded = described_class.decode(encoded, prefix: "T", key: custom_key)
          recovered_count += 1 if decoded == value
        rescue Strata::UserFacingId::Error
          # Acceptable: wrong key triggered parity mismatch.
        end
      end

      expect(recovered_count).to eq(0)
    end
  end

  describe ".normalize_prefix" do
    it "uppercases lowercase input" do
      expect(described_class.normalize_prefix("claim")).to eq("CLAIM")
    end

    it "strips surrounding whitespace" do
      expect(described_class.normalize_prefix("  t  ")).to eq("T")
    end

    it "accepts alphanumeric prefixes" do
      [ "T", "CLAIM", "A1", "X9Z" ].each do |prefix|
        expect { described_class.normalize_prefix(prefix) }.not_to raise_error
      end
    end

    it "rejects prefixes with non-alphanumeric characters" do
      [ "A-B", "A B", "A_B", "A.B", "A!" ].each do |bad_prefix|
        expect { described_class.normalize_prefix(bad_prefix) }.to raise_error(Strata::UserFacingId::FormatError)
      end
    end

    it "rejects empty and nil prefixes" do
      [ "", "   ", nil ].each do |bad_prefix|
        expect { described_class.normalize_prefix(bad_prefix) }.to raise_error(Strata::UserFacingId::FormatError)
      end
    end
  end

  describe ".decode input validation" do
    let(:valid_encoded) { described_class.encode(12_345, prefix: "T", key: test_key) }

    it "raises for missing prefix" do
      no_prefix = valid_encoded.sub(/\AT-/, "")

      expect { described_class.decode(no_prefix, prefix: "T", key: test_key) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises for an extra segment" do
      extra = "#{valid_encoded}-A00"

      expect { described_class.decode(extra, prefix: "T", key: test_key) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises for a missing segment" do
      truncated = valid_encoded.split("-")[0..2].join("-")

      expect { described_class.decode(truncated, prefix: "T", key: test_key) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises for a malformed segment shape" do
      [
        "T-Y1-B33-N91",    # short segment
        "T-Y011-B33-N91",  # long segment
        "T-YY1-B33-N91",   # two letters
        "T-Y01-B33-9N1"    # digit-led segment
      ].each do |bad_input|
        expect { described_class.decode(bad_input, prefix: "T", key: test_key) }.to raise_error(Strata::UserFacingId::FormatError),
          "expected FormatError for #{bad_input.inspect}"
      end
    end

    it "raises for empty input" do
      expect { described_class.decode("", prefix: "T", key: test_key) }.to raise_error(Strata::UserFacingId::FormatError)
    end
  end

  describe ".encode input validation" do
    it "raises for a negative integer" do
      expect { described_class.encode(-1, prefix: "T", key: test_key) }.to raise_error(RangeError)
    end

    it "truncates a float through Integer() coercion" do
      # Kernel#Integer accepts a Float and truncates toward zero, so 1.5 encodes
      # as 1. This is a quirk of the underlying coercion; documented here so a
      # future change to stricter coercion is a deliberate decision.
      expect(described_class.encode(1.5, prefix: "T", key: test_key))
        .to eq(described_class.encode(1, prefix: "T", key: test_key))
    end

    it "raises for nil" do
      expect { described_class.encode(nil, prefix: "T", key: test_key) }.to raise_error(ArgumentError)
    end

    it "raises for a non-numeric string" do
      expect { described_class.encode("foo", prefix: "T", key: test_key) }.to raise_error(ArgumentError)
    end

    it "accepts an integer-as-string" do
      expect(described_class.encode("12345", prefix: "T", key: test_key))
        .to eq(described_class.encode(12_345, prefix: "T", key: test_key))
    end

    it "validates the prefix at encode time" do
      expect { described_class.encode(12_345, prefix: "BAD-PREFIX", key: test_key) }
        .to raise_error(Strata::UserFacingId::FormatError)
    end
  end

  describe "custom alphabet" do
    let(:no_o_alphabet) { %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z] }
    let(:full_alphabet) { ("A".."Z").to_a }
    let(:no_o_max) { (no_o_alphabet.length * Strata::UserFacingId::Alphabet::DIGITS_PER_LETTER)**3 / 16 - 1 }

    it "round-trips a representative sweep under a custom alphabet" do
      [ 0, 1, 12_345, 1_000_000, no_o_max ].each do |value|
        encoded = described_class.encode(value, prefix: "T", key: test_key, alphabet: no_o_alphabet)
        expect(described_class.decode(encoded, prefix: "T", key: test_key, alphabet: no_o_alphabet)).to eq(value)
      end
    end

    it "never emits excluded letters in encoded output" do
      encodings = (0...10_000).map do |value|
        described_class.encode(value, prefix: "T", key: test_key, alphabet: no_o_alphabet)
      end

      expect(encodings).to all(match(/\AT-[A-HJ-NP-Z]\d{2}-[A-HJ-NP-Z]\d{2}-[A-HJ-NP-Z]\d{2}\z/))
      encodings.each { |encoded| expect(encoded).not_to include("O") }
    end

    it "produces a different encoded value than the default alphabet" do
      custom = described_class.encode(12_345, prefix: "T", key: test_key, alphabet: no_o_alphabet)
      default = described_class.encode(12_345, prefix: "T", key: test_key)

      expect(custom).not_to eq(default)
    end

    it "raises FormatError for an encoded ID containing letters outside the configured alphabet" do
      expect do
        described_class.decode("T-O00-A00-A00", prefix: "T", key: test_key, alphabet: no_o_alphabet)
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises RangeError beyond the per-alphabet capacity" do
      expect { described_class.encode(no_o_max + 1, prefix: "T", key: test_key, alphabet: no_o_alphabet) }
        .to raise_error(RangeError)
    end

    it "caps capacity at Feistel::DOMAIN_SIZE for a full 26-letter alphabet" do
      feistel_max = Strata::UserFacingId::Feistel::DOMAIN_SIZE - 1

      expect { described_class.encode(feistel_max, prefix: "T", key: test_key, alphabet: full_alphabet) }
        .not_to raise_error
      expect { described_class.encode(feistel_max + 1, prefix: "T", key: test_key, alphabet: full_alphabet) }
        .to raise_error(RangeError)
    end

    describe "26-letter alphabet decode safety" do
      it "raises FormatError (not RangeError) when a crafted ID's data half overflows the Feistel ceiling" do
        # 2600^3 - 1 has a data half (>>4) of 1,098,499,999 — above the 2^30 - 1 ceiling.
        expect do
          described_class.decode("T-Z99-Z99-Z99", prefix: "T", key: test_key, alphabet: full_alphabet)
        end.to raise_error(Strata::UserFacingId::FormatError)
      end

      it "raises FormatError on overflow even when parity matches" do
        # Build a crafted ID whose data half is above capacity but whose parity is
        # consistent. The capacity check must fire before the parity check.
        base = full_alphabet.length * Strata::UserFacingId::Alphabet::DIGITS_PER_LETTER
        overflow_data = Strata::UserFacingId::Feistel::DOMAIN_SIZE
        parity = Strata::UserFacingId::Parity.calculate(overflow_data, base: base)
        packed = (overflow_data << 4) | parity
        remaining = packed
        segments = []
        Strata::UserFacingId::Codec::SEGMENT_COUNT.times do
          remaining, chunk = remaining.divmod(base)
          segments.unshift(Strata::UserFacingId::Alphabet.encode(chunk, alphabet: full_alphabet))
        end
        crafted = ([ "T" ] + segments).join("-")

        expect do
          described_class.decode(crafted, prefix: "T", key: test_key, alphabet: full_alphabet)
        end.to raise_error(Strata::UserFacingId::FormatError)
      end
    end

    it "allows 'I' to appear in encoded output when the alphabet includes it" do
      found_i = (0...1_000).any? do |value|
        described_class.encode(value, prefix: "T", key: test_key, alphabet: full_alphabet).include?("I")
      end

      expect(found_i).to be(true)
    end

    describe "golden table under a 24-letter (no-O) alphabet" do
      # Locked once captured from the first implementation run; future changes to
      # alphabet plumbing, base math, or parity weighting must update this table
      # deliberately — any change breaks every issued no-O ID downstream.
      [
        { sequence: 0,         encoded: "T-C43-W57-F51" },
        { sequence: 1,         encoded: "T-Q02-B25-B79" },
        { sequence: 12_345,    encoded: "T-Y40-R61-U57" },
        { sequence: 1_000_000, encoded: "T-G02-G94-U21" }
      ].each do |case_data|
        it "encodes sequence=#{case_data[:sequence]} to #{case_data[:encoded]}" do
          encoded = described_class.encode(case_data[:sequence], prefix: "T", key: test_key,
            alphabet: %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z])

          expect(encoded).to eq(case_data[:encoded])
        end
      end
    end
  end

  describe "regression: default alphabet is unchanged" do
    it "produces identical output whether :alphabet is omitted or explicitly default" do
      [ 0, 1, 12_345, 1_000_000, described_class::MAX_VALUE ].each do |value|
        explicit = described_class.encode(value, prefix: "T", key: test_key,
          alphabet: Strata::UserFacingId::Alphabet::DEFAULT)

        expect(explicit).to eq(described_class.encode(value, prefix: "T", key: test_key))
      end
    end
  end
end
