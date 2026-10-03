# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strata::UserFacingId::Parity do
  describe "constants" do
    it "locks the segment weights and four-bit mask" do
      # Changing weights would invalidate every checksum on previously issued IDs.
      expect(described_class::WEIGHTS).to eq([ 1, 3, 7 ])
      expect(described_class::MASK).to eq(0b1111)
    end
  end

  describe ".calculate" do
    it "returns 0 for the zero data value" do
      expect(described_class.calculate(0)).to eq(0)
    end

    it "returns known checksums for anchor values" do
      # These anchors lock the current weighting scheme.
      {
        0 => 0,
        1 => 1,
        Strata::UserFacingId::Alphabet::BASE - 1 => 3,
        12_345 => 5,
        Strata::UserFacingId::Codec::MAX_VALUE => 7
      }.each do |value, expected|
        expect(described_class.calculate(value)).to eq(expected),
          "expected calculate(#{value}) to eq #{expected}"
      end
    end

    it "always returns a four-bit value" do
      [ 0, 1, 12_345, 1_000_000, Strata::UserFacingId::Codec::MAX_VALUE ].each do |value|
        expect(described_class.calculate(value)).to be_between(0, 15)
      end
    end
  end

  describe ".append and .split" do
    it "round-trip data values across the domain" do
      [ 0, 1, 99, 100, 2499, 12_345, 1_000_000, Strata::UserFacingId::Codec::MAX_VALUE ].each do |value|
        packed = described_class.append(value)
        data, parity = described_class.split(packed)

        expect(data).to eq(value)
        expect(parity).to eq(described_class.calculate(value))
      end
    end

    it "places the parity in the low four bits" do
      packed = described_class.append(12_345)

      expect(packed & described_class::MASK).to eq(described_class.calculate(12_345))
      expect(packed >> 4).to eq(12_345)
    end
  end

  describe ".valid? and .validate!" do
    it "accepts matching parity" do
      expect(described_class.valid?(12_345, described_class.calculate(12_345))).to be(true)
      expect { described_class.validate!(12_345, described_class.calculate(12_345)) }.not_to raise_error
    end

    it "rejects mismatched parity" do
      correct = described_class.calculate(12_345)
      wrong = (correct + 1) % 16

      expect(described_class.valid?(12_345, wrong)).to be(false)
      expect { described_class.validate!(12_345, wrong) }.to raise_error(Strata::UserFacingId::ParityError)
    end

    it "rejects any non-matching parity in the four-bit range" do
      correct = described_class.calculate(12_345)
      (0..15).reject { |candidate| candidate == correct }.each do |wrong|
        expect(described_class.valid?(12_345, wrong)).to be(false)
      end
    end
  end

  describe "single-digit tampering" do
    it "changes the checksum so common transcription errors are caught" do
      # The last segment dominates the lowest-weighted chunk; flipping one of its
      # digits should change the parity for the values we care about.
      [ 1, 12_345, 1_000_000 ].each do |value|
        original_parity = described_class.calculate(value)
        # Adjust the lowest base-2500 chunk by 1, simulating a one-digit edit.
        tampered_value = value + 1
        next if tampered_value > Strata::UserFacingId::Codec::MAX_VALUE

        expect(described_class.calculate(tampered_value)).not_to eq(original_parity)
      end
    end
  end

  describe ".calculate with a custom base" do
    it "matches the default-base calculation when base equals Alphabet::BASE" do
      [ 0, 1, 12_345, 1_000_000 ].each do |value|
        expect(described_class.calculate(value, base: Strata::UserFacingId::Alphabet::BASE))
          .to eq(described_class.calculate(value))
      end
    end

    it "chunks against the configured base for non-default alphabets" do
      # For value = 12345 under base 2400: chunks = [345, 5, 0]; weighted sum = 345*1 + 5*3 + 0*7 = 360; 360 % 16 = 8.
      expect(described_class.calculate(12_345, base: 2400)).to eq(8)
    end

    it "produces a four-bit value across the custom-base domain" do
      [ 0, 1, 12_345, 1_000_000 ].each do |value|
        expect(described_class.calculate(value, base: 2400)).to be_between(0, 15)
      end
    end
  end
end
