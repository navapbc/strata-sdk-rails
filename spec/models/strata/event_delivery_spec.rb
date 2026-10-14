# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::EventDelivery do
  describe 'defaults' do
    it 'starts pending with no attempts, schedule, enqueue, error, or completion' do
      expect(create(:strata_event_delivery)).to have_attributes(
        status: 'pending', attempts: 0, next_attempt_at: nil, enqueued_at: nil, last_error: nil, completed_at: nil
      )
    end
  end

  describe 'statuses' do
    it 'has the statuses from the durable events spec' do
      expect(described_class.statuses)
        .to eq({ 'pending' => 0, 'succeeded' => 1, 'failed' => 2, 'no_match' => 3, 'dead' => 4 })
    end
  end

  describe 'sweep index' do
    it 'covers exactly the pending and failed statuses, so reordering the enum fails here' do
      definition = described_class.connection.select_value(<<~SQL)
        SELECT indexdef FROM pg_indexes WHERE indexname = 'index_strata_event_deliveries_on_sweep'
      SQL
      statuses = described_class.statuses.values_at('pending', 'failed')

      expect(definition).to include("ARRAY[#{statuses.join(', ')}]")
    end
  end

  describe 'validations' do
    it 'requires an event' do
      delivery = build(:strata_event_delivery, event: nil)

      expect(delivery).not_to be_valid
      expect(delivery.errors[:event]).to be_present
    end

    it 'requires a subscriber' do
      delivery = build(:strata_event_delivery, subscriber: nil)

      expect(delivery).not_to be_valid
      expect(delivery.errors[:subscriber]).to be_present
    end

    it 'rejects an unknown status' do
      delivery = build(:strata_event_delivery, status: 'retrying')

      expect(delivery).not_to be_valid
      expect(delivery.errors[:status]).to be_present
    end

    it 'does not allow negative attempts' do
      delivery = build(:strata_event_delivery, attempts: -1)

      expect(delivery).not_to be_valid
      expect(delivery.errors[:attempts]).to be_present
    end

    it 'allows one delivery per subscriber for an event' do
      existing = create(:strata_event_delivery)
      duplicate = build(:strata_event_delivery, event: existing.event, subscriber: existing.subscriber)

      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same subscriber on different events' do
      existing = create(:strata_event_delivery)

      expect(build(:strata_event_delivery, subscriber: existing.subscriber)).to be_valid
    end
  end

  describe 'last_error' do
    it 'truncates errors longer than the limit' do
      delivery = create(:strata_event_delivery, last_error: 'x' * 5_000)

      expect(delivery.reload.last_error.length).to eq(described_class::LAST_ERROR_LIMIT)
    end
  end

  describe 'state changes' do
    it 'can be updated while its event is readonly' do
      delivery = create(:strata_event_delivery)

      delivery.update!(status: :succeeded, attempts: 1, completed_at: Time.current)

      expect(delivery.reload).to be_succeeded
    end
  end
end
