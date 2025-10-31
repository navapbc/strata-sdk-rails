# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Determinable do
  let(:test_form) { create(:test_application_form) }

  describe 'included behavior' do
    it 'adds has_many determinations association' do
      expect(test_form).to respond_to(:determinations)
    end

    it 'allows dependent destroy' do
      create(:strata_determination, subject: test_form)
      expect { test_form.destroy }.to change(Strata::Determination, :count).by(-1)
    end
  end

  describe '#record_determination!' do
    let(:determined_at) { Date.new(2025, 01, 15).to_date }
    let(:data) { { "key_1" => "value_1", "key_2" => "value_2" } }

    context 'with automated determination' do
      it 'creates a determination record with correct attributes' do
        expect {
          test_form.record_determination!(
            decision_method: :automated,
            reasons: [ "pregnant_member" ],
            outcome: :automated_exemption,
            determined_at: determined_at,
            determination_data: data
          )
        }.to change { test_form.determinations.count }.by(1)

        determination = test_form.determinations.first
        expect(determination.decision_method).to eq('automated')
        expect(determination.reasons).to eq([ "pregnant_member" ])
        expect(determination.outcome).to eq('automated_exemption')
        expect(determination.determination_data).to eq(data)
        expect(determination.determined_by_id).to be_nil
        expect(determination.determined_at).to eq(determined_at)
      end
    end

    it 'raises an error if required parameters are missing' do
      expect {
        test_form.record_determination!(
          decision_method: :automated,
          reasons: [ "test" ],
          outcome: :automated_exemption
          # missing determination_data
        )
      }.to raise_error(ArgumentError)
    end

    it 'raises an error if determination_data is empty' do
      expect {
        test_form.record_determination!(
          decision_method: :automated,
          reasons: [ "test" ],
          outcome: :automated_exemption,
          determination_data: {}
        )
      }.to raise_error(ArgumentError)
    end
  end

  describe 'scope delegation through concern' do
    let(:test_form) { create(:test_application_form) }
    let(:other_form) { create(:test_application_form) }

    before do
      create(:strata_determination, subject: test_form, decision_method: :automated)
      create(:strata_determination, subject: other_form, decision_method: :automated)
    end

    it 'filters determinations by subject through has_many' do
      expect(test_form.determinations.count).to eq(1)
      expect(other_form.determinations.count).to eq(1)
    end
  end
end
