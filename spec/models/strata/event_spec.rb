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

    it 'reloads large integers exactly, as integers' do
      reloaded = create(:strata_event, payload: { 'big' => 2**70 }).reload.payload['big']

      expect(reloaded).to eq(2**70)
      expect(reloaded).to be_an(Integer)
    end

    it 'stores the payload as Strata::Events::Payload.serialize returns it' do
      payload = { case_id: 'abc', nested: [ 1, nil ], submitted_at: Time.utc(2026, 10, 14, 12) }
      event = create(:strata_event, payload: payload)

      expect(described_class.find(event.id).payload)
        .to eq({ 'case_id' => 'abc', 'nested' => [ 1, nil ], 'submitted_at' => '2026-10-14T12:00:00.000000Z' })
    end

    it 'rejects a missing payload before saving it' do
      expect { create(:strata_event, payload: nil) }
        .to raise_error(Strata::Events::Payload::InvalidPayloadError, /must be a Hash/)
    end

    it 'rejects a payload that breaks the payload contract before saving it' do
      expect { create(:strata_event, payload: { kase: TestCase.new }) }
        .to raise_error(Strata::Events::Payload::InvalidPayloadError, /publish its id instead/)
    end

    it 'rejects a payload changed in place to break the contract before saving it' do
      event = build(:strata_event)
      event.payload['state'] = :approved

      expect { event.save! }.to raise_error(Strata::Events::Payload::InvalidPayloadError, /state/)
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
