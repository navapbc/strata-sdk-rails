# frozen_string_literal: true

require 'rails_helper'

module EventManagerSpecHandlers
  def self.create_case_then_fail(_event)
    TestCase.create!(business_process_current_step: 'from_failing_handler')
    raise StandardError, 'handler failed'
  end
end

RSpec.describe Strata::EventManager do
  let(:subscriptions) { [] }

  def subscribe(event_key, callback)
    subscriptions << described_class.subscribe(event_key, callback)
  end

  after do
    subscriptions.each { |subscription| described_class.unsubscribe(subscription) }
  end

  describe 'when a subscriber raises' do
    let(:failing_handler) { EventManagerSpecHandlers.method(:create_case_then_fail) }

    before do
      allow(Rails.error).to receive(:report)
      subscribe('SomethingHappened', failing_handler)
    end

    it 'does not raise to the publisher' do
      expect { described_class.publish('SomethingHappened', { case_id: 'abc' }) }.not_to raise_error
    end

    it "rolls back the subscriber's database changes" do
      described_class.publish('SomethingHappened', { case_id: 'abc' })

      expect(TestCase.where(business_process_current_step: 'from_failing_handler')).not_to exist
    end

    it "keeps the publisher's write made in the same transaction" do
      publisher_case = nil
      ActiveRecord::Base.transaction do
        publisher_case = TestCase.create!(business_process_current_step: 'from_publisher')
        described_class.publish('SomethingHappened', { case_id: publisher_case.id })
      end

      expect(TestCase.exists?(publisher_case.id)).to be(true)
      expect(TestCase.where(business_process_current_step: 'from_failing_handler')).not_to exist
    end

    it 'still runs the other subscribers' do
      received = []
      subscribe('SomethingHappened', ->(event) { received << event })

      described_class.publish('SomethingHappened', { case_id: 'abc' })

      expect(received).to eq([ { name: 'SomethingHappened', payload: { case_id: 'abc' } } ])
    end

    it 'reports the error as handled with the event and subscriber' do
      described_class.publish('SomethingHappened', { case_id: 'abc' })

      expect(Rails.error).to have_received(:report).with(
        an_instance_of(StandardError).and(having_attributes(message: 'handler failed')),
        handled: true,
        severity: :error,
        context: { event: 'SomethingHappened', subscriber: 'EventManagerSpecHandlers.create_case_then_fail' }
      )
    end

    it 'reports an anonymous subscriber by its class name' do
      subscribe('SomethingElseHappened', ->(_event) { raise StandardError, 'lambda failed' })

      described_class.publish('SomethingElseHappened', {})

      expect(Rails.error).to have_received(:report).with(
        an_instance_of(StandardError),
        handled: true,
        severity: :error,
        context: { event: 'SomethingElseHappened', subscriber: 'Proc' }
      )
    end

    it 'logs the error with the event, subscriber, and backtrace' do
      allow(Rails.logger).to receive(:error)

      described_class.publish('SomethingHappened', { case_id: 'abc' })

      expect(Rails.logger).to have_received(:error).with(
        a_string_including(
          'SomethingHappened',
          'EventManagerSpecHandlers.create_case_then_fail',
          'handler failed',
          'event_manager_spec.rb'
        )
      )
    end
  end

  describe 'when a subscriber raises an exception that is not a StandardError' do
    let(:fatal_error_class) { Class.new(Exception) } # rubocop:disable Lint/InheritException

    before do
      allow(Rails.error).to receive(:report)
      error_class = fatal_error_class
      subscribe('SomethingHappened', ->(_event) { raise error_class, 'fatal' })
    end

    it 'propagates to the publisher without reporting it' do
      expect { described_class.publish('SomethingHappened', {}) }.to raise_error(fatal_error_class, 'fatal')
      expect(Rails.error).not_to have_received(:report)
    end
  end

  describe '.publish return value' do
    it 'returns nil even when a subscriber fails' do
      allow(Rails.error).to receive(:report)
      subscribe('SomethingHappened', ->(_event) { raise StandardError, 'lambda failed' })

      expect(described_class.publish('SomethingHappened', {})).to be_nil
    end
  end

  describe '.publish_reporting_failures' do
    before do
      allow(Rails.error).to receive(:report)
    end

    it 'returns no failures when every subscriber succeeds' do
      subscribe('SomethingHappened', ->(_event) { })

      expect(described_class.publish_reporting_failures('SomethingHappened', {})).to eq([])
    end

    it 'returns no failures when nothing is subscribed' do
      expect(described_class.publish_reporting_failures('NobodyListens', {})).to eq([])
    end

    it 'delivers the payload to subscribers like publish does' do
      received = []
      subscribe('SomethingHappened', ->(event) { received << event })

      described_class.publish_reporting_failures('SomethingHappened', { case_id: 'abc' })

      expect(received).to eq([ { name: 'SomethingHappened', payload: { case_id: 'abc' } } ])
    end

    it 'returns the subscriber and error for each failing subscriber' do
      subscribe('SomethingHappened', EventManagerSpecHandlers.method(:create_case_then_fail))
      subscribe('SomethingHappened', ->(_event) { })
      subscribe('SomethingHappened', ->(_event) { raise ArgumentError, 'lambda failed' })

      failures = described_class.publish_reporting_failures('SomethingHappened', {})

      expect(failures).to contain_exactly(
        { subscriber: 'EventManagerSpecHandlers.create_case_then_fail', error: an_instance_of(StandardError).and(having_attributes(message: 'handler failed')) },
        { subscriber: 'Proc', error: an_instance_of(ArgumentError).and(having_attributes(message: 'lambda failed')) }
      )
    end

    it 'does not include failures from events published by a subscriber' do
      subscribe('InnerEvent', ->(_event) { raise StandardError, 'inner failed' })
      subscribe('OuterEvent', ->(_event) { described_class.publish('InnerEvent', {}) })

      outer_failures = described_class.publish_reporting_failures('OuterEvent', {})

      expect(outer_failures).to eq([])
      expect(Rails.error).to have_received(:report).with(
        having_attributes(message: 'inner failed'), hash_including(context: hash_including(event: 'InnerEvent'))
      )
    end
  end
end
