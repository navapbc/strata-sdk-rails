# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strata::Attributes::UserFacingIdAttribute do
  let(:sequence_value) { 12_345 }
  let(:record) { TestRecord.create!(user_facing_id_sequence: sequence_value) }
  let(:user_facing_id) { record.user_facing_id }

  it "returns nil when the sequence column is nil" do
    expect(TestRecord.new.user_facing_id).to be_nil
  end

  it "formats the sequence column as a user-facing ID" do
    expect(record.user_facing_id).to eq(user_facing_id)
  end

  it "uses the database default to assign sequence values" do
    first_record = TestRecord.create!
    second_record = TestRecord.create!

    expect(first_record.user_facing_id_sequence).to be_present
    expect(second_record.user_facing_id_sequence).to be > first_record.user_facing_id_sequence
    expect(first_record.user_facing_id).to be_present
    expect(second_record.user_facing_id).not_to eq(first_record.user_facing_id)
  end

  describe "database integration" do
    it "stores the backing value as an integer sequence, not a formatted ID" do
      persisted_record = TestRecord.create!
      raw_sequence_value = TestRecord.connection.select_value(
        "SELECT user_facing_id_sequence FROM test_records WHERE id = #{TestRecord.connection.quote(persisted_record.id)}"
      )

      expect(TestRecord.column_names).to include("user_facing_id_sequence")
      expect(TestRecord.column_names).not_to include("user_facing_id")
      expect(raw_sequence_value).to be_an(Integer)
      expect(raw_sequence_value).to eq(persisted_record.user_facing_id_sequence)
    end

    it "exposes the user-facing ID in the expected format" do
      persisted_record = TestRecord.create!

      expect(persisted_record.user_facing_id).to match(/\AT-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}\z/)
    end

    it "keeps the same user-facing ID after reloading from the database" do
      persisted_record = TestRecord.create!
      formatted_id = persisted_record.user_facing_id

      expect(persisted_record.reload.user_facing_id).to eq(formatted_id)
    end

    it "queries by the backing integer sequence column" do
      persisted_record = TestRecord.create!

      expect(TestRecord.where(user_facing_id: persisted_record.user_facing_id).to_sql).to include(
        "\"test_records\".\"user_facing_id_sequence\""
      )
    end

    it "finds the correct record through native ActiveRecord query methods" do
      matching_record = TestRecord.create!
      other_record = TestRecord.create!

      expect(TestRecord.find_by(user_facing_id: matching_record.user_facing_id)).to eq(matching_record)
      expect(TestRecord.find_by!(user_facing_id: matching_record.user_facing_id)).to eq(matching_record)
      expect(TestRecord.where(user_facing_id: matching_record.user_facing_id)).to contain_exactly(matching_record)
      expect(TestRecord.where(user_facing_id: matching_record.user_facing_id)).not_to include(other_record)
    end

    it "enforces uniqueness at the database layer" do
      TestRecord.create!(user_facing_id_sequence: sequence_value)

      expect do
        TestRecord.create!(user_facing_id_sequence: sequence_value)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "with a different prefix" do
    let(:claim_record) { TestRecord.create!(claim_user_facing_id_sequence: sequence_value) }
    let(:claim_user_facing_id) { claim_record.claim_user_facing_id }

    it "formats the user-facing ID with the configured prefix" do
      expect(claim_user_facing_id).to match(/\ACLAIM-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}\z/)
    end

    it "finds the correct record by the prefixed user-facing ID" do
      other_record = TestRecord.create!(claim_user_facing_id_sequence: 54_321)

      expect(TestRecord.find_by!(claim_user_facing_id: claim_user_facing_id)).to eq(claim_record)
      expect(TestRecord.where(claim_user_facing_id: claim_user_facing_id)).to contain_exactly(claim_record)
      expect(TestRecord.where(claim_user_facing_id: claim_user_facing_id)).not_to include(other_record)
    end

    it "finds the correct record with native ActiveRecord query methods" do
      other_record = TestRecord.create!(claim_user_facing_id_sequence: 54_321)

      expect(TestRecord.find_by(claim_user_facing_id: claim_user_facing_id)).to eq(claim_record)
      expect(TestRecord.where(claim_user_facing_id: claim_user_facing_id)).to contain_exactly(claim_record)
      expect(TestRecord.where(claim_user_facing_id: claim_user_facing_id)).not_to include(other_record)
    end

    it "does not allow lookup through an attribute with a different prefix" do
      expect(TestRecord.find_by(user_facing_id: claim_user_facing_id)).to be_nil
      expect(TestRecord.where(user_facing_id: claim_user_facing_id)).to be_empty

      expect do
        TestRecord.find_by!(user_facing_id: claim_user_facing_id)
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "finds a record by user-facing ID" do
    expect(TestRecord.find_by!(user_facing_id: user_facing_id)).to eq(record)
  end

  it "returns nil from the native non-bang finder for invalid IDs" do
    expect(TestRecord.find_by(user_facing_id: "not-an-id")).to be_nil
  end

  it "finds a record when the user-facing ID input is lowercase" do
    expect(TestRecord.find_by!(user_facing_id: user_facing_id.downcase)).to eq(record)
  end

  it "queries records by user-facing ID with native where" do
    other_record = TestRecord.create!(user_facing_id_sequence: 54_321)

    expect(TestRecord.where(user_facing_id: user_facing_id)).to contain_exactly(record)
    expect(TestRecord.where(user_facing_id: user_facing_id)).not_to include(other_record)
  end

  it "returns an empty relation for invalid IDs" do
    record

    expect(TestRecord.where(user_facing_id: "not-an-id")).to be_empty
  end

  it "raises RecordNotFound for invalid IDs with the native bang finder" do
    expect do
      TestRecord.find_by!(user_facing_id: "not-an-id")
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "handles prefix mismatches consistently across lookup APIs" do
    wrong_prefix_id = user_facing_id.sub(/\AT-/, "X-")

    expect(TestRecord.find_by(user_facing_id: wrong_prefix_id)).to be_nil
    expect(TestRecord.where(user_facing_id: wrong_prefix_id)).to be_empty

    expect do
      TestRecord.find_by!(user_facing_id: wrong_prefix_id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "raises RecordNotFound for finder parity mismatches" do
    tampered = user_facing_id.sub(/\d\z/) { |digit| ((digit.to_i + 1) % 10).to_s }

    expect do
      TestRecord.find_by!(user_facing_id: tampered)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  describe "writer behavior" do
    let(:formatted_id) { TestRecord.new(user_facing_id_sequence: sequence_value).user_facing_id }

    it "decodes a formatted ID into the backing sequence" do
      target = TestRecord.new
      target.user_facing_id = formatted_id

      expect(target.user_facing_id_sequence).to eq(sequence_value)
    end

    it "accepts integer assignment as a sequence value" do
      target = TestRecord.new
      target.user_facing_id = sequence_value

      expect(target.user_facing_id_sequence).to eq(sequence_value)
    end

    it "treats nil as a sequence reset" do
      target = TestRecord.new(user_facing_id_sequence: sequence_value)
      target.user_facing_id = nil

      expect(target.user_facing_id_sequence).to be_nil
    end

    it "treats blank strings as nil" do
      target = TestRecord.new(user_facing_id_sequence: sequence_value)
      target.user_facing_id = ""

      expect(target.user_facing_id_sequence).to be_nil
    end

    it "accepts lowercase formatted IDs" do
      target = TestRecord.new
      target.user_facing_id = formatted_id.downcase

      expect(target.user_facing_id_sequence).to eq(sequence_value)
    end

    it "raises FormatError for malformed strings" do
      expect do
        TestRecord.new.user_facing_id = "not-an-id"
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for prefix mismatches" do
      wrong_prefix_id = formatted_id.sub(/\AT-/, "X-")

      expect do
        TestRecord.new.user_facing_id = wrong_prefix_id
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises ParityError for tampered IDs" do
      tampered = formatted_id.sub(/\d\z/) { |digit| ((digit.to_i + 1) % 10).to_s }

      expect do
        TestRecord.new.user_facing_id = tampered
      end.to raise_error(Strata::UserFacingId::ParityError)
    end

    it "leaves the permissive cast path unaffected for find_by" do
      expect(TestRecord.find_by(user_facing_id: "not-an-id")).to be_nil
    end

    it "raises FormatError when an integer-as-string is assigned" do
      # The writer treats any non-blank string as a formatted ID, so "12345"
      # is parsed (and fails) rather than coerced to the integer 12345.
      expect do
        TestRecord.new.user_facing_id = "12345"
      end.to raise_error(Strata::UserFacingId::FormatError)
    end
  end

  describe "golden persisted ID" do
    it "renders sequence 12345 under prefix 'T' as the exact codec golden value" do
      # Locks the end-to-end Rails integration against the codec golden table.
      record = TestRecord.create!(user_facing_id_sequence: 12_345)

      expect(record.user_facing_id).to eq("T-D67-B66-O48")
      expect(record.reload.user_facing_id).to eq("T-D67-B66-O48")
    end

    it "renders sequence 12345 under prefix 'CLAIM' as the exact codec golden value" do
      record = TestRecord.create!(claim_user_facing_id_sequence: 12_345)

      expect(record.claim_user_facing_id).to eq("CLAIM-Z75-N82-O60")
    end
  end

  describe "multiple persisted records" do
    it "round-trips every record through find_by across a sample of 20 records" do
      records = Array.new(20) { TestRecord.create! }

      expect(records.map(&:user_facing_id).uniq.size).to eq(20)
      records.each do |target|
        expect(TestRecord.find_by!(user_facing_id: target.user_facing_id)).to eq(target)
      end
    end
  end

  describe "out-of-range sequence values" do
    it "raises RangeError when the backing sequence exceeds MAX_VALUE" do
      # bigserial can outgrow the encodable space; if it ever does, the reader
      # raises rather than returning a garbled ID.
      out_of_range = Strata::UserFacingId::Codec::MAX_VALUE + 1
      record = TestRecord.new(user_facing_id_sequence: out_of_range)

      expect { record.user_facing_id }.to raise_error(RangeError)
    end
  end

  describe "custom :key option" do
    let(:custom_key) { 0xdead_beef }
    let(:model_class) do
      key = custom_key
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :keyed_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: key
      end
    end

    it "flows the custom key through encode" do
      # Matches the codec golden-table entry for prefix T, custom key, seq 12345.
      record = model_class.new(user_facing_id_sequence: 12_345)

      expect(record.keyed_id).to eq("T-P03-O83-R39")
    end

    it "produces a different encoding than the default-key attribute on the same sequence" do
      record = TestRecord.new(user_facing_id_sequence: 12_345)
      custom_record = model_class.new(user_facing_id_sequence: 12_345)

      expect(custom_record.keyed_id).not_to eq(record.user_facing_id)
    end

    it "flows the custom key through the writer" do
      record = model_class.new
      record.keyed_id = "T-P03-O83-R39"

      expect(record.user_facing_id_sequence).to eq(12_345)
    end
  end

  describe "custom :sequence_column option" do
    let(:model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        # Explicit sequence_column points the attribute at the CLAIM column.
        user_facing_id_attribute :case_id,
          prefix: "CASE",
          sequence_column: :claim_user_facing_id_sequence,
          key: 0x9b6d_42a7
      end
    end

    it "reads and writes through the configured sequence column" do
      record = model_class.new(claim_user_facing_id_sequence: 12_345)

      expect(record.case_id).to match(/\ACASE-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}-[A-HJ-Z]\d{2}\z/)
      expect(record.case_id).to eq("CASE-D67-B66-O48")
    end

    it "exposes the attribute as an alias for the configured sequence column" do
      record = model_class.new(claim_user_facing_id_sequence: 12_345)

      expect(record.case_id).to eq(model_class.new(case_id: 12_345).case_id)
    end
  end

  describe "class-definition-time validation" do
    it "raises FormatError when the prefix contains disallowed characters" do
      expect do
        Class.new(ApplicationRecord) do
          self.table_name = "test_records"
          include Strata::Attributes

          user_facing_id_attribute :bad_id, prefix: "BAD-PREFIX", key: 0x9b6d_42a7
        end
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for an empty prefix" do
      expect do
        Class.new(ApplicationRecord) do
          self.table_name = "test_records"
          include Strata::Attributes

          user_facing_id_attribute :bad_id, prefix: "", key: 0x9b6d_42a7
        end
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises KeyError when prefix is omitted" do
      expect do
        Class.new(ApplicationRecord) do
          self.table_name = "test_records"
          include Strata::Attributes

          user_facing_id_attribute :bad_id, key: 0x9b6d_42a7
        end
      end.to raise_error(KeyError)
    end

    it "raises KeyError when key is omitted" do
      expect do
        Class.new(ApplicationRecord) do
          self.table_name = "test_records"
          include Strata::Attributes

          user_facing_id_attribute :bad_id, prefix: "T"
        end
      end.to raise_error(KeyError)
    end
  end

  describe "custom :alphabet option" do
    let(:no_o_alphabet) { %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z] }
    let(:model_class) do
      alphabet = no_o_alphabet
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :no_o_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: alphabet
      end
    end

    it "formats IDs using only the configured alphabet" do
      record = model_class.create!(user_facing_id_sequence: 12_345)

      expect(record.no_o_id).to match(/\AT-[A-HJ-NP-Z]\d{2}-[A-HJ-NP-Z]\d{2}-[A-HJ-NP-Z]\d{2}\z/)
      expect(record.no_o_id).not_to include("O")
    end

    it "produces a different encoding than the default-alphabet attribute on the same sequence" do
      default_record = TestRecord.new(user_facing_id_sequence: 12_345)
      custom_record = model_class.new(user_facing_id_sequence: 12_345)

      expect(custom_record.no_o_id).not_to eq(default_record.user_facing_id)
    end

    it "round-trips through the writer" do
      formatted = model_class.new(user_facing_id_sequence: 12_345).no_o_id
      target = model_class.new
      target.no_o_id = formatted

      expect(target.user_facing_id_sequence).to eq(12_345)
    end

    it "raises FormatError when the writer receives a letter outside the alphabet" do
      expect do
        model_class.new.no_o_id = "T-O00-A00-A00"
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "supports find_by through the custom-alphabet attribute" do
      record = model_class.create!(user_facing_id_sequence: 12_345)

      expect(model_class.find_by!(no_o_id: record.no_o_id)).to eq(record)
      expect(model_class.where(no_o_id: record.no_o_id)).to contain_exactly(record)
    end

    it "combines :alphabet with :key" do
      custom_key = 0xdead_beef
      alphabet = no_o_alphabet
      keyed_class = Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :keyed_no_o_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: custom_key,
          alphabet: alphabet
      end

      keyed_record = keyed_class.new(user_facing_id_sequence: 12_345)

      expect(keyed_record.keyed_no_o_id).not_to include("O")
      expect(keyed_record.keyed_no_o_id).not_to eq(model_class.new(user_facing_id_sequence: 12_345).no_o_id)
    end

    it "reduces capacity according to alphabet length" do
      per_alphabet_max = (no_o_alphabet.length * Strata::UserFacingId::Alphabet::DIGITS_PER_LETTER)**3 / 16 - 1

      expect { model_class.new(user_facing_id_sequence: per_alphabet_max).no_o_id }.not_to raise_error
      expect { model_class.new(user_facing_id_sequence: per_alphabet_max + 1).no_o_id }.to raise_error(RangeError)
    end

    it "accepts a full 26-letter alphabet that includes 'I'" do
      full_alphabet = ("A".."Z").to_a
      klass = Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :full_alpha_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: full_alphabet
      end

      encodings = (1..200).map { |seq| klass.new(user_facing_id_sequence: seq).full_alpha_id }

      expect(encodings.any? { |encoded| encoded.include?("I") }).to be(true)
    end

    it "caps a 26-letter alphabet at Feistel::DOMAIN_SIZE - 1" do
      full_alphabet = ("A".."Z").to_a
      klass = Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :full_alpha_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: full_alphabet
      end
      feistel_max = Strata::UserFacingId::Feistel::DOMAIN_SIZE - 1

      expect { klass.new(user_facing_id_sequence: feistel_max).full_alpha_id }.not_to raise_error
      expect { klass.new(user_facing_id_sequence: feistel_max + 1).full_alpha_id }.to raise_error(RangeError)
    end

    it "omitting :alphabet produces output identical to today" do
      # Regression guard: existing attributes (and persisted IDs) must keep their encoding.
      expect(TestRecord.new(user_facing_id_sequence: 12_345).user_facing_id).to eq("T-D67-B66-O48")
    end
  end

  describe "alphabet validation at class-definition time" do
    def define_class_with(alphabet)
      bad_alphabet = alphabet
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :bad_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: bad_alphabet
      end
    end

    it "raises FormatError for duplicate letters" do
      expect { define_class_with(%w[A A B C D]) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for lowercase letters" do
      expect { define_class_with(%w[a b c d]) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for digits or symbols" do
      expect { define_class_with(%w[A B 1 2]) }.to raise_error(Strata::UserFacingId::FormatError)
      expect { define_class_with(%w[A B - C]) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for multi-character entries" do
      expect { define_class_with(%w[AA BB CC]) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for an empty alphabet" do
      expect { define_class_with([]) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError for an alphabet longer than 26 characters" do
      too_long = ("A".."Z").to_a + [ "A" ]

      expect { define_class_with(too_long) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError when alphabet is not an Array" do
      expect { define_class_with("ABCDEFG") }.to raise_error(Strata::UserFacingId::FormatError)
      expect { define_class_with(nil) }.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "accepts a 26-letter alphabet" do
      expect { define_class_with(("A".."Z").to_a) }.not_to raise_error
    end

    it "accepts a single-letter alphabet" do
      # Smallest valid alphabet — capacity collapses to 100^3/16 = 62,500 but it's still valid.
      expect { define_class_with(%w[A]) }.not_to raise_error
    end
  end

  describe "alphabet immutability" do
    it "is unaffected when the caller mutates the alphabet array after class definition" do
      alphabet = %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z]
      klass = Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :no_o_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: alphabet
      end
      original_encoding = klass.new(user_facing_id_sequence: 12_345).no_o_id

      alphabet.clear
      alphabet.concat(%w[Z Y X])

      expect(klass.new(user_facing_id_sequence: 12_345).no_o_id).to eq(original_encoding)
    end

    it "does not freeze the caller's alphabet array" do
      alphabet = %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z]
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :no_o_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: alphabet
      end

      expect(alphabet).not_to be_frozen
    end
  end

  describe "26-letter alphabet query safety" do
    let(:full_alphabet) { ("A".."Z").to_a }
    let(:full_alpha_class) do
      alphabet = full_alphabet
      Class.new(ApplicationRecord) do
        self.table_name = "test_records"
        include Strata::Attributes

        user_facing_id_attribute :full_alpha_id,
          prefix: "T",
          sequence_column: :user_facing_id_sequence,
          key: 0x9b6d_42a7,
          alphabet: alphabet
      end
    end

    it "returns nil from find_by for a crafted overflow ID" do
      full_alpha_class.create!(user_facing_id_sequence: 12_345)

      expect(full_alpha_class.find_by(full_alpha_id: "T-Z99-Z99-Z99")).to be_nil
    end

    it "returns an empty relation from where for a crafted overflow ID" do
      full_alpha_class.create!(user_facing_id_sequence: 12_345)

      expect(full_alpha_class.where(full_alpha_id: "T-Z99-Z99-Z99")).to be_empty
    end

    it "raises RecordNotFound (not RangeError) from find_by! for a crafted overflow ID" do
      full_alpha_class.create!(user_facing_id_sequence: 12_345)

      expect do
        full_alpha_class.find_by!(full_alpha_id: "T-Z99-Z99-Z99")
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "sequence column setter loudness" do
    it "raises FormatError when assigning a numeric string to the sequence column" do
      expect do
        TestRecord.new.user_facing_id_sequence = "12345"
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "raises FormatError when assigning a non-id string to the sequence column" do
      expect do
        TestRecord.new.user_facing_id_sequence = "not-an-id"
      end.to raise_error(Strata::UserFacingId::FormatError)
    end

    it "still accepts a formatted ID on the sequence column" do
      formatted = TestRecord.new(user_facing_id_sequence: 12_345).user_facing_id
      target = TestRecord.new
      target.user_facing_id_sequence = formatted

      expect(target.user_facing_id_sequence).to eq(12_345)
    end

    it "still accepts an integer on the sequence column" do
      target = TestRecord.new
      target.user_facing_id_sequence = 12_345

      expect(target.user_facing_id_sequence).to eq(12_345)
    end

    it "still accepts nil on the sequence column" do
      target = TestRecord.new(user_facing_id_sequence: 12_345)
      target.user_facing_id_sequence = nil

      expect(target.user_facing_id_sequence).to be_nil
    end

    it "keeps the query path permissive: find_by returns nil for malformed input" do
      expect(TestRecord.find_by(user_facing_id: "not-an-id")).to be_nil
    end

    it "keeps the query path permissive: where returns empty for malformed input" do
      expect(TestRecord.where(user_facing_id: "not-an-id")).to be_empty
    end

    it "keeps the query path permissive: find_by! raises RecordNotFound for malformed input" do
      expect do
        TestRecord.find_by!(user_facing_id: "not-an-id")
      end.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
