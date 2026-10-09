# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strata::UserFacingId::Alphabet do
  describe "constants" do
    it "locks the default alphabet to a 25-letter, A-Z-without-I sequence" do
      # Reordering or adding letters would invalidate every previously issued ID,
      # so the alphabet must stay fixed once issuance begins.
      expect(described_class::DEFAULT).to eq(%w[A B C D E F G H J K L M N O P Q R S T U V W X Y Z])
      expect(described_class::DEFAULT).not_to include("I")
      expect(described_class::DEFAULT.length).to eq(25)
    end

    it "locks the per-segment capacity" do
      expect(described_class::DIGITS_PER_LETTER).to eq(100)
      expect(described_class::BASE).to eq(2500)
    end
  end

  describe ".encode" do
    it "produces the expected letter-and-two-digit segment for anchor values" do
      {
        0 => "A00",
        1 => "A01",
        99 => "A99",
        100 => "B00",
        # Confirms the "I" gap: index 8 in DEFAULT is "J", so 800 must encode to "J00".
        800 => "J00",
        2499 => "Z99"
      }.each do |value, expected|
        expect(described_class.encode(value)).to eq(expected)
      end
    end

    it "round-trips every value in the segment domain" do
      (0...described_class::BASE).each do |value|
        expect(described_class.decode(described_class.encode(value))).to eq(value)
      end
    end

    it "produces distinct outputs for every value in the segment domain" do
      encoded = (0...described_class::BASE).map { |value| described_class.encode(value) }

      expect(encoded.uniq.size).to eq(described_class::BASE)
    end

    it "raises for values outside the segment domain" do
      expect { described_class.encode(-1) }.to raise_error(RangeError)
      expect { described_class.encode(described_class::BASE) }.to raise_error(RangeError)
    end

    it "raises for non-integer values" do
      [ nil, "0", 1.5, :symbol ].each do |bad_value|
        expect { described_class.encode(bad_value) }.to raise_error(RangeError)
      end
    end
  end

  describe ".decode" do
    it "accepts lowercase input" do
      expect(described_class.decode("a00")).to eq(0)
      expect(described_class.decode("z99")).to eq(2499)
    end

    it "raises FormatError when the letter is not in the alphabet" do
      # "I" is intentionally omitted to avoid confusion with the digit 1.
      expect { described_class.decode("I00") }.to raise_error(Strata::UserFacingId::FormatError)
      expect { described_class.decode("i99") }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for malformed segments" do
      [
        "",
        "100",   # leading digit instead of letter
        "A0",    # one digit
        "A001",  # three digits
        "AA0",   # two letters
        "A-0",   # contains a separator
        "A0A"    # trailing letter
      ].each do |bad_segment|
        expect { described_class.decode(bad_segment) }.to raise_error(Strata::UserFacingId::FormatError),
          "expected FormatError for #{bad_segment.inspect}"
      end
    end

    it "raises FormatError for non-string input that does not coerce to a valid segment" do
      [ nil, 0 ].each do |bad_value|
        expect { described_class.decode(bad_value) }.to raise_error(Strata::UserFacingId::FormatError)
      end
    end
  end

  describe "with a custom alphabet" do
    let(:no_o_alphabet) { %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z] }
    let(:full_alphabet) { ("A".."Z").to_a }

    it "encodes using only letters from the custom alphabet" do
      capacity = no_o_alphabet.length * described_class::DIGITS_PER_LETTER
      encodings = (0...capacity).map { |value| described_class.encode(value, alphabet: no_o_alphabet) }

      expect(encodings).to all(match(/\A[A-HJ-NP-Z]\d{2}\z/))
      expect(encodings.uniq.size).to eq(capacity)
    end

    it "round-trips every value within the custom alphabet's capacity" do
      capacity = no_o_alphabet.length * described_class::DIGITS_PER_LETTER
      (0...capacity).each do |value|
        encoded = described_class.encode(value, alphabet: no_o_alphabet)
        expect(described_class.decode(encoded, alphabet: no_o_alphabet)).to eq(value)
      end
    end

    it "raises RangeError for values beyond the custom alphabet's capacity" do
      capacity = no_o_alphabet.length * described_class::DIGITS_PER_LETTER

      expect { described_class.encode(capacity, alphabet: no_o_alphabet) }.to raise_error(RangeError)
    end

    it "raises FormatError on decode for letters not in the custom alphabet" do
      expect { described_class.decode("O00", alphabet: no_o_alphabet) }
        .to raise_error(Strata::UserFacingId::FormatError)
    end

    it "supports a full 26-letter alphabet that includes 'I'" do
      # Index 8 in a full A-Z alphabet is "I"; default alphabet maps index 8 to "J".
      expect(described_class.encode(800, alphabet: full_alphabet)).to eq("I00")
      expect(described_class.decode("I00", alphabet: full_alphabet)).to eq(800)
    end
  end
end
