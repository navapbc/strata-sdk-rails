# frozen_string_literal: true

require 'rails_helper'
require 'support/durable_events'

RSpec.describe Strata::EventManager do
  include DurableEventsHelpers

  let(:subscriptions) { [] }

  before do
    stub_const('EventManagerSpecHandlers', Module.new do
      def self.create_case_then_fail(_event)
        TestCase.create!(business_process_current_step: 'from_failing_handler')
        raise StandardError, 'handler failed'
      end

      def self.handle(_event); end

      def self.handle_again(_event); end
    end)
  end

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

  describe 'durable subscriber registry' do
    let(:handler) { EventManagerSpecHandlers.method(:handle) }
    let(:other_handler) { EventManagerSpecHandlers.method(:handle_again) }

    context 'when durability is enabled' do
      around do |example|
        with_durable_events { example.run }
      end

      it 'registers a named module method under its subscriber key' do
        subscribe('SomethingHappened', handler)

        expect(described_class.subscriber_keys('SomethingHappened')).to eq([ 'EventManagerSpecHandlers.handle' ])
      end

      it 'lists every subscriber of an event in subscription order' do
        subscribe('SomethingHappened', other_handler)
        subscribe('SomethingHappened', handler)

        expect(described_class.subscriber_keys('SomethingHappened'))
          .to eq([ 'EventManagerSpecHandlers.handle_again', 'EventManagerSpecHandlers.handle' ])
      end

      it 'registers one subscriber under each event it subscribes to' do
        subscribe('SomethingHappened', handler)
        subscribe('SomethingElseHappened', handler)

        expect(described_class.subscriber_keys('SomethingHappened')).to eq([ 'EventManagerSpecHandlers.handle' ])
        expect(described_class.subscriber_keys('SomethingElseHappened')).to eq([ 'EventManagerSpecHandlers.handle' ])
      end

      it 'has no subscriber keys for an event nobody subscribes to' do
        expect(described_class.subscriber_keys('NothingHappened')).to eq([])
      end

      it 'returns the registered callback for an event and subscriber key' do
        subscribe('SomethingHappened', handler)

        expect(described_class.subscriber('SomethingHappened', 'EventManagerSpecHandlers.handle')).to eq(handler)
      end

      it 'still delivers events to the subscriber in process' do
        received = []
        stub_const('RecordingHandlers', Module.new do
          define_singleton_method(:handle) { |event| received << event }
        end)
        subscribe('SomethingHappened', RecordingHandlers.method(:handle))

        described_class.publish('SomethingHappened', { case_id: 'abc' })

        expect(received).to eq([ { name: 'SomethingHappened', payload: { case_id: 'abc' } } ])
      end

      describe 'rejecting subscribers that cannot be addressed by name' do
        it 'rejects a lambda with a message explaining how to migrate' do
          expect { subscribe('SomethingHappened', ->(_event) { }) }
            .to raise_error(Strata::Events::NonDurableSubscriberError, /SomethingHappened.*named class or module method/m)
        end

        it 'rejects a proc' do
          expect { subscribe('SomethingHappened', proc { |_event| }) }
            .to raise_error(Strata::Events::NonDurableSubscriberError)
        end

        it 'rejects a method on an instance' do
          instance = Class.new { def handle(_event); end }.new

          expect { subscribe('SomethingHappened', instance.method(:handle)) }
            .to raise_error(Strata::Events::NonDurableSubscriberError)
        end

        it 'rejects an object that responds to call' do
          callable = Class.new { def call(_event); end }.new

          expect { subscribe('SomethingHappened', callable) }
            .to raise_error(Strata::Events::NonDurableSubscriberError)
        end

        it 'rejects a method on an anonymous class' do
          anonymous = Class.new { def self.handle(_event); end }

          expect { subscribe('SomethingHappened', anonymous.method(:handle)) }
            .to raise_error(Strata::Events::NonDurableSubscriberError)
        end

        it 'rejects a method on a class whose name now refers to a different class, as after reloading' do
          stale = Class.new { def self.handle(_event); end }
          stub_const('ReloadedHandlers', stale)
          stub_const('ReloadedHandlers', Class.new { def self.handle(_event); end })

          expect { subscribe('SomethingHappened', stale.method(:handle)) }
            .to raise_error(Strata::Events::NonDurableSubscriberError)
        end

        it 'does not deliver events to a rejected subscriber' do
          received = []
          begin
            subscribe('SomethingHappened', ->(event) { received << event })
          rescue Strata::Events::NonDurableSubscriberError
            nil
          end

          described_class.publish('SomethingHappened', {})

          expect(received).to be_empty
        end
      end

      describe 'duplicate subscribers' do
        it 'rejects the same subscriber key subscribing to the same event twice' do
          subscribe('SomethingHappened', handler)

          expect { subscribe('SomethingHappened', handler) }
            .to raise_error(Strata::Events::DuplicateSubscriberError, /EventManagerSpecHandlers.handle.*SomethingHappened/)
        end

        it 'keeps delivering the event once to the original subscription' do
          allow(EventManagerSpecHandlers).to receive(:handle)
          subscribe('SomethingHappened', EventManagerSpecHandlers.method(:handle))
          begin
            subscribe('SomethingHappened', EventManagerSpecHandlers.method(:handle))
          rescue Strata::Events::DuplicateSubscriberError
            nil
          end

          described_class.publish('SomethingHappened', {})

          expect(EventManagerSpecHandlers).to have_received(:handle).once
        end
      end

      describe 'looking up a subscriber' do
        it 'raises for a subscriber key that was never registered, without loading it by name' do
          expect { described_class.subscriber('SomethingHappened', 'Kernel.system') }
            .to raise_error(Strata::Events::UnknownSubscriberError, /Kernel.system.*SomethingHappened/)
        end

        it 'raises for a subscriber key registered only for a different event' do
          subscribe('SomethingElseHappened', handler)

          expect { described_class.subscriber('SomethingHappened', 'EventManagerSpecHandlers.handle') }
            .to raise_error(Strata::Events::UnknownSubscriberError)
        end
      end

      describe 'unsubscribing' do
        it 'removes the subscriber key from the event' do
          subscription = described_class.subscribe('SomethingHappened', handler)
          subscribe('SomethingHappened', other_handler)

          described_class.unsubscribe(subscription)

          expect(described_class.subscriber_keys('SomethingHappened')).to eq([ 'EventManagerSpecHandlers.handle_again' ])
          expect { described_class.subscriber('SomethingHappened', 'EventManagerSpecHandlers.handle') }
            .to raise_error(Strata::Events::UnknownSubscriberError)
        end

        it 'allows the same subscriber key to subscribe again' do
          described_class.unsubscribe(described_class.subscribe('SomethingHappened', handler))

          subscribe('SomethingHappened', handler)

          expect(described_class.subscriber_keys('SomethingHappened')).to eq([ 'EventManagerSpecHandlers.handle' ])
        end

        it 'ignores a subscription that was already removed' do
          subscription = described_class.subscribe('SomethingHappened', handler)
          described_class.unsubscribe(subscription)

          expect { described_class.unsubscribe(subscription) }.not_to raise_error
        end

        it 'clears every subscriber key on unsubscribe_all' do
          subscribe('SomethingHappened', handler)
          subscribe('SomethingElseHappened', other_handler)

          described_class.unsubscribe_all

          expect(described_class.subscriber_keys('SomethingHappened')).to eq([])
          expect(described_class.subscriber_keys('SomethingElseHappened')).to eq([])
        end
      end
    end

    context 'when durability is disabled' do
      around do |example|
        with_durable_events(false) { example.run }
      end

      it 'does not register subscriber keys' do
        subscribe('SomethingHappened', handler)

        expect(described_class.subscriber_keys('SomethingHappened')).to eq([])
      end

      it 'still accepts anonymous subscribers' do
        expect { subscribe('SomethingHappened', ->(_event) { }) }.not_to raise_error
      end

      it 'delivers to a named subscriber once per subscription, as before' do
        allow(EventManagerSpecHandlers).to receive(:handle)
        subscribe('SomethingHappened', EventManagerSpecHandlers.method(:handle))
        subscribe('SomethingHappened', EventManagerSpecHandlers.method(:handle))

        described_class.publish('SomethingHappened', {})

        expect(EventManagerSpecHandlers).to have_received(:handle).twice
      end
    end
  end
end
