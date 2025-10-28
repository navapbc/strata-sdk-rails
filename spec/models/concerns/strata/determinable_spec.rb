# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Determinable do
  let(:test_case_class) do
    Class.new(Strata::Case) do
      include Strata::Determinable
    end
  end

  before do
    stub_const('TestDeterminableCase', test_case_class)
  end

  describe 'included behavior' do
    let(:test_case) { create(:test_case) }

    it 'adds has_many determinations association' do
      expect(test_case).to respond_to(:determinations)
    end

    it 'allows dependent destroy' do
      create(:strata_determination, subject: test_case)
      expect { test_case.destroy }.to change(Strata::Determination, :count).by(-1)
    end
  end

  describe '#record_determination!' do
    let(:test_case) { create(:test_case) }
    let(:determined_at) { Date.new(2025, 01, 15).to_date }
    let(:data) { { "key_1" => "value_1", "key_2" => "value_2" } }

    context 'with automated determination' do
      it 'creates a determination record with correct attributes' do
        expect {
          test_case.record_determination!(
            decision_method: :automated,
            reason: "pregnant_member",
            outcome: :automated_exemption,
            determined_at: determined_at,
            determination_data: data
          )
        }.to change { test_case.determinations.count }.by(1)

        determination = test_case.determinations.first
        expect(determination.decision_method).to eq('automated')
        expect(determination.reason).to eq('pregnant_member')
        expect(determination.outcome).to eq('automated_exemption')
        expect(determination.determination_data).to eq(data)
        expect(determination.determined_by_id).to be_nil
        expect(determination.determined_at).to eq(determined_at)
      end
    end

    it 'raises an error if required parameters are missing' do
      expect {
        test_case.record_determination!(
          decision_method: :automated,
          reason: "test",
          outcome: :automated_exemption
          # missing determination_data
        )
      }.to raise_error(ArgumentError)
    end

    it 'raises an error if determination_data is empty' do
      expect {
        test_case.record_determination!(
          decision_method: :automated,
          reason: "test",
          outcome: :automated_exemption,
          determination_data: {}
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe 'scope delegation through concern' do
    let(:test_case) { create(:test_case) }
    let(:other_case) { create(:test_case) }

    before do
      create(:strata_determination, subject: test_case, decision_method: :automated)
      create(:strata_determination, subject: other_case, decision_method: :automated)
    end

    it 'filters determinations by subject through has_many' do
      expect(test_case.determinations.count).to eq(1)
      expect(other_case.determinations.count).to eq(1)
    end
  end
end
