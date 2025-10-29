# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Determination do
  describe 'associations' do
    it { is_expected.to belong_to(:subject).dependent(false) }
  end

  describe 'validations' do
    subject { build(:strata_determination) }

    it { is_expected.to validate_presence_of(:decision_method) }
    it { is_expected.to validate_presence_of(:reason) }
    it { is_expected.to validate_presence_of(:outcome) }
    it { is_expected.to validate_presence_of(:determination_data) }
    it { is_expected.to validate_presence_of(:determined_at) }
  end

  describe 'polymorphic association' do
    let(:test_form) { create(:test_application_form) }
    let(:determination) { create(:strata_determination, subject: test_form) }

    it 'stores and retrieves polymorphic subject' do
      expect(determination.subject).to eq(test_form)
      expect(determination.subject_type).to eq('TestApplicationForm')
      expect(determination.subject_id).to eq(test_form.id)
    end
  end

  describe 'scopes' do
    let(:test_form_alpha) { create(:test_application_form) }
    let(:test_form_bravo) { create(:test_application_form) }
    let(:passport_form) { create(:passport_application_form) }

    let(:determination_form_1_auto) do
      build(:strata_determination, subject: test_form_alpha, decision_method: :automated,
                                    reason: "age_under_19", outcome: :automated_exemption,
                                    determined_at: Date.new(2025, 1, 10))
    end

    let(:determination_form_1_review) do
      build(:strata_determination, subject: test_form_alpha, decision_method: :staff_review,
                                    reason: "requirements_verification", outcome: :requirements_met,
                                    determined_at: Date.new(2025, 1, 15))
    end

    let(:determination_form_2_attest) do
      build(:strata_determination, subject: test_form_bravo, decision_method: :attestation,
                                    reason: "user_declaration", outcome: :accepted,
                                    determined_at: Date.new(2025, 1, 20))
    end

    let(:determination_passport_auto) do
      build(:strata_determination, subject: passport_form, decision_method: :automated,
                                    reason: "us_citizen", outcome: :automated_exemption,
                                    determined_at: Date.new(2025, 1, 25))
    end

    before do
      determination_form_1_auto.save!
      determination_form_1_review.save!
      determination_form_2_attest.save!
      determination_passport_auto.save!
    end

    describe 'for_subject' do
      # before do
      #   determination_form_1_auto.save!
      #   determination_form_1_review.save!
      #   determination_form_2_attest.save!
      #   determination_passport_auto.save!
      # end

      it 'returns only determinations for the given subject' do
        results = described_class.for_subject(test_form_alpha)
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'filters correctly when given a different subject' do
        results = described_class.for_subject(test_form_bravo)
        expect(results).to contain_exactly(determination_form_2_attest)
      end

      it 'returns empty result when subject has no determinations' do
        new_form = create(:test_application_form)
        results = described_class.for_subject(new_form)
        expect(results).to be_empty
      end
    end

    describe 'for_subjects' do
      # before do
      #   determination_form_1_auto.save!
      #   determination_form_1_review.save!
      #   determination_form_2_attest.save!
      #   determination_passport_auto.save!
      # end

      it 'returns determinations for all given subjects' do
        results = described_class.for_subjects([ test_form_alpha, test_form_bravo ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review, determination_form_2_attest)
      end

      it 'handles single subject in array' do
        results = described_class.for_subjects([ test_form_alpha ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'returns empty when no subjects provided' do
        results = described_class.for_subjects([])
        expect(results).to be_empty
      end
    end

    describe 'for_subject_type' do
      # before do
      #   determination_form_1_auto
      #   determination_form_1_review
      #   determination_form_2_attest
      #   determination_passport_auto
      # end

      it 'filters by class object' do
        results = described_class.for_subject_type(TestApplicationForm)
        expect(results.count).to eq(3)
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review, determination_form_2_attest)
      end

      it 'filters by string class name' do
        results = described_class.for_subject_type('TestApplicationForm')
        expect(results.count).to eq(3)
      end

      it 'filters by symbol class name' do
        results = described_class.for_subject_type(:TestApplicationForm)
        expect(results.count).to eq(3)
      end

      it 'filters by a different type' do
        results = described_class.for_subject_type(PassportApplicationForm)
        expect(results).to contain_exactly(determination_passport_auto)
      end
    end

    describe 'for_subject_id' do
      # before do
      #   determination_form_1_auto
      #   determination_form_1_review
      #   determination_form_2_attest
      #   determination_passport_auto
      # end

      it 'filters by subject_id alone' do
        results = described_class.for_subject_id(test_form_alpha.id)
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'filters by subject_id and type' do
        results = described_class.for_subject_id(test_form_alpha.id, TestApplicationForm)
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'returns empty when id does not match any subject' do
        fake_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
        results = described_class.for_subject_id(fake_id)
        expect(results).to be_empty
      end

      it 'handles type as string' do
        results = described_class.for_subject_id(test_form_alpha.id, 'TestApplicationForm')
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end
    end

    describe 'with_decision_method' do
      it 'filters by single symbol' do
        results = described_class.with_decision_method(:automated)
        expect(results).to contain_exactly(determination_form_1_auto, determination_passport_auto)
      end

      it 'filters by single string' do
        results = described_class.with_decision_method('automated')
        expect(results).to contain_exactly(determination_form_1_auto, determination_passport_auto)
      end

      it 'filters by array of methods' do
        results = described_class.with_decision_method([ :automated, :staff_review ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review, determination_passport_auto)
      end

      it 'filters by array of strings' do
        results = described_class.with_decision_method([ 'automated', 'attestation' ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_2_attest, determination_passport_auto)
      end

      it 'returns empty when no determinations match' do
        results = described_class.with_decision_method(:nonexistent)
        expect(results).to be_empty
      end
    end

    describe 'with_reason' do
      it 'filters by single reason' do
        results = described_class.with_reason('age_under_19')
        expect(results).to contain_exactly(determination_form_1_auto)
      end

      it 'filters by array of reasons' do
        results = described_class.with_reason([ 'age_under_19', 'requirements_verification' ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'returns empty when no determinations match' do
        results = described_class.with_reason('nonexistent_reason')
        expect(results).to be_empty
      end
    end

    describe 'with_outcome' do
      it 'filters by single outcome' do
        results = described_class.with_outcome('automated_exemption')
        expect(results).to contain_exactly(determination_form_1_auto, determination_passport_auto)
      end

      it 'filters by array of outcomes' do
        results = described_class.with_outcome([ :automated_exemption, :requirements_met ])
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review, determination_passport_auto)
      end

      it 'returns empty when no determinations match' do
        results = described_class.with_outcome('nonexistent_outcome')
        expect(results).to be_empty
      end
    end

    describe 'determined_by' do
      let(:user_1_id) { SecureRandom.uuid }
      let(:user_2_id) { SecureRandom.uuid }

      let(:determination_by_first_user) do
        build(:strata_determination, subject: test_form_alpha, determined_by_id: user_1_id)
      end

      let(:determination_by_second_user) do
        build(:strata_determination, subject: test_form_alpha, determined_by_id: user_2_id)
      end

      let(:automated_determination) do
        build(:strata_determination, subject: test_form_alpha, determined_by_id: nil)
      end

      before do
        determination_by_first_user.save!
        determination_by_second_user.save!
        automated_determination.save!
      end

      it 'filters determinations by determined_by_id' do
        results = described_class.determined_by(user_1_id)
        expect(results).to contain_exactly(determination_by_first_user)
      end

      it 'returns empty when no determinations match' do
        results = described_class.determined_by(SecureRandom.uuid)
        expect(results).to be_empty
      end

      it 'does not include automated determinations (nil determined_by_id)' do
        results = described_class.determined_by(user_1_id)
        expect(results).not_to include(automated_determination)
      end
    end

    describe 'determined_before' do
      it 'returns determinations before the given date' do
        cutoff = Date.new(2025, 1, 16)
        results = described_class.determined_before(cutoff)
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'excludes determinations on or after the cutoff' do
        cutoff = Date.new(2025, 1, 15)
        results = described_class.determined_before(cutoff)
        expect(results).to contain_exactly(determination_form_1_auto)
      end

      it 'returns empty when all determinations are after the cutoff' do
        cutoff = Date.new(2024, 12, 31)
        results = described_class.determined_before(cutoff)
        expect(results).to be_empty
      end
    end

    describe 'determined_after' do
      it 'returns determinations after the given date' do
        cutoff = Date.new(2025, 1, 14)
        results = described_class.determined_after(cutoff)
        expect(results).to contain_exactly(determination_form_1_review, determination_form_2_attest, determination_passport_auto)
      end

      it 'excludes determinations on or before the cutoff' do
        cutoff = Date.new(2025, 1, 15)
        results = described_class.determined_after(cutoff)
        expect(results).to contain_exactly(determination_form_2_attest, determination_passport_auto)
      end

      it 'returns empty when all determinations are before the cutoff' do
        cutoff = Date.new(2025, 2, 1)
        results = described_class.determined_after(cutoff)
        expect(results).to be_empty
      end
    end

    describe 'determined_between' do
      it 'returns determinations within the date range (inclusive)' do
        start_date = Date.new(2025, 1, 12)
        end_date = Date.new(2025, 1, 18)
        results = described_class.determined_between(start_date, end_date)
        expect(results).to contain_exactly(determination_form_1_review)
      end

      it 'includes determinations on the start boundary' do
        start_date = Date.new(2025, 1, 10)
        end_date = Date.new(2025, 1, 14)
        results = described_class.determined_between(start_date, end_date)
        expect(results).to contain_exactly(determination_form_1_auto)
      end

      it 'includes determinations on the end boundary' do
        start_date = Date.new(2025, 1, 15)
        end_date = Date.new(2025, 1, 20)
        results = described_class.determined_between(start_date, end_date)
        expect(results).to contain_exactly(determination_form_1_review, determination_form_2_attest)
      end

      it 'returns empty when no determinations fall in range' do
        start_date = Date.new(2025, 2, 1)
        end_date = Date.new(2025, 2, 10)
        results = described_class.determined_between(start_date, end_date)
        expect(results).to be_empty
      end
    end

    describe 'latest_first' do
      it 'orders determinations by determined_at descending' do
        results = described_class.latest_first
        expect(results.first).to eq(determination_passport_auto)
        expect(results.last).to eq(determination_form_1_auto)
      end
    end

    describe 'oldest_first' do
      it 'orders determinations by determined_at ascending' do
        results = described_class.oldest_first
        expect(results.first).to eq(determination_form_1_auto)
        expect(results.last).to eq(determination_passport_auto)
      end
    end

    describe 'chaining scopes' do
      it 'chains for_subject with with_decision_method' do
        results = described_class.for_subject(test_form_alpha).with_decision_method(:automated)
        expect(results).to contain_exactly(determination_form_1_auto)
      end

      it 'chains multiple scopes for complex queries' do
        results = described_class
                   .for_subject_type(TestApplicationForm)
                   .with_decision_method([ :automated, :staff_review ])
                   .determined_between(Date.new(2025, 1, 10), Date.new(2025, 1, 16))
        expect(results).to contain_exactly(determination_form_1_auto, determination_form_1_review)
      end

      it 'chains with latest_first ordering' do
        results = described_class.for_subject(test_form_alpha).latest_first
        expect(results.first).to eq(determination_form_1_review)
        expect(results.last).to eq(determination_form_1_auto)
      end
    end
  end
end
