# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Event do
  describe 'validations' do
    it 'is valid with a name and publication time' do
      expect(build(:strata_event)).to be_valid
    end

    it 'requires a name' do
      event = build(:strata_event, name: nil)

      expect(event).not_to be_valid
      expect(event.errors[:name]).to be_present
    end

    it 'requires a publication time' do
      event = build(:strata_event, published_at: nil)

      expect(event).not_to be_valid
      expect(event.errors[:published_at]).to be_present
    end
  end

  describe 'payload' do
    it 'defaults to an empty hash' do
      expect(described_class.new.payload).to eq({})
    end

    it 'stores and reloads plain JSON' do
      event = create(:strata_event, payload: { 'case_id' => 'abc', 'nested' => [ 1, nil ] })

      expect(event.reload.payload).to eq({ 'case_id' => 'abc', 'nested' => [ 1, nil ] })
    end
  end

  describe 'publisher' do
    it 'is optional' do
      expect(build(:strata_event, publisher: nil)).to be_valid
    end

    it 'records the publishing record' do
      kase = TestCase.create!

      event = create(:strata_event, publisher: kase)

      expect(event.reload.publisher).to eq(kase)
    end
  end

  describe 'deliveries' do
    it 'lists the deliveries for the event' do
      event = create(:strata_event)
      first = create(:strata_event_delivery, event: event, subscriber: 'FirstProcess.handle_event')
      second = create(:strata_event_delivery, event: event, subscriber: 'SecondProcess.handle_event')

      expect(event.deliveries).to contain_exactly(first, second)
    end
  end

  describe 'immutability' do
    let(:event) { create(:strata_event) }

    it 'is readonly once persisted' do
      expect(event.readonly?).to be true
    end

    it 'is not readonly when newly built' do
      expect(build(:strata_event).readonly?).to be false
    end

    it 'raises when attempting to update an attribute' do
      expect { event.update!(name: 'Tampered') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'raises when attempting to destroy' do
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  describe 'pruning' do
    it 'deletes the deliveries of an event deleted in SQL' do
      event = create(:strata_event)
      create(:strata_event_delivery, event: event)

      described_class.where(id: event.id).delete_all

      expect(Strata::EventDelivery.where(event_id: event.id)).not_to exist
    end
  end
end
