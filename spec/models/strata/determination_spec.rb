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
    let(:test_case) { create(:test_case) }
    let(:determination) { create(:strata_determination, subject: test_case) }

    it 'stores and retrieves polymorphic subject' do
      expect(determination.subject).to eq(test_case)
      expect(determination.subject_type).to eq('TestCase')
      expect(determination.subject_id).to eq(test_case.id)
    end
  end
end
