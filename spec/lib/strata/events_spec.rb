# frozen_string_literal: true

require 'rails_helper'
require 'support/durable_events'

RSpec.describe Strata::Events do
  include DurableEventsHelpers

  let(:subscriptions) { [] }

  before do
    stub_const('EventsSpecHandlers', Module.new do
      def self.handle(_event); end
    end)
  end

  def subscribe(event_key, callback)
    subscriptions << Strata::EventManager.subscribe(event_key, callback)
  end

  describe '.durable' do
    it 'defaults to false' do
      expect(described_class.durable).to be(false)
    end

    it 'can be enabled while no subscriptions are active' do
      with_durable_events do
        expect(described_class.durable).to be(true)
      end
    end
  end

  describe '.durable=' do
    around do |example|
      with_durable_events(false) { example.run }
    end

    it 'refuses to change once a subscription is active' do
      subscribe('SomethingHappened', EventsSpecHandlers.method(:handle))

      expect { described_class.durable = true }
        .to raise_error(Strata::Events::ConfigurationError, /subscriptions/)
      expect(described_class.durable).to be(false)
    end

    it 'refuses an assignment that would not change the value once a subscription is active' do
      subscribe('SomethingHappened', EventsSpecHandlers.method(:handle))

      expect { described_class.durable = false }.to raise_error(Strata::Events::ConfigurationError)
    end

    it 'can be changed again after every subscription is unsubscribed' do
      subscribe('SomethingHappened', EventsSpecHandlers.method(:handle))
      subscribe('SomethingElseHappened', ->(_event) { })
      subscriptions.each { |subscription| Strata::EventManager.unsubscribe(subscription) }

      described_class.durable = true

      expect(described_class.durable).to be(true)
    end

    it 'can be changed again after unsubscribe_all, as during code reloading' do
      subscribe('SomethingHappened', EventsSpecHandlers.method(:handle))
      Strata::EventManager.unsubscribe_all

      described_class.durable = true

      expect(described_class.durable).to be(true)
    end

    it 'does not count an unsubscribe of an already removed subscription twice' do
      first = Strata::EventManager.subscribe('SomethingHappened', EventsSpecHandlers.method(:handle))
      subscribe('SomethingElseHappened', EventsSpecHandlers.method(:handle))
      Strata::EventManager.unsubscribe(first)
      Strata::EventManager.unsubscribe(first)

      expect { described_class.durable = true }.to raise_error(Strata::Events::ConfigurationError)
    end

    it 'does not count a subscription that durable mode rejected' do
      described_class.durable = true
      expect { subscribe('SomethingHappened', ->(_event) { }) }
        .to raise_error(Strata::Events::NonDurableSubscriberError)

      described_class.durable = false

      expect(described_class.durable).to be(false)
    end

    it 'rejects values other than true or false' do
      expect { described_class.durable = 'true' }
        .to raise_error(Strata::Events::ConfigurationError, /true or false/)
      expect(described_class.durable).to be(false)
    end
  end
end
