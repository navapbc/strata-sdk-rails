# frozen_string_literal: true

require 'rails_helper'

# Covers Phase 1 item 1.2 (rescue at the publish boundary), per spec.md 6.1 and
# 9.1, plus characterization of the publish/subscribe behavior the rescue must
# not change.
#
# Why the rescue exists: publish is called from after_create/after_update, not
# after_commit, and instrument runs subscribers inline on the same thread. So a
# step error that escapes publish unwinds the caller's save! — for
# ApplicationForm#publish_created that means rejecting a submitted form. Phase 1
# keeps the domain write and gives up the transition; Phase 3 removes this
# rescue once handlers run in a job and a raise is what drives the retry.
RSpec.describe Strata::EventManager do
  let(:event_name) { "SpecEvent#{SecureRandom.hex(4)}" }

  after { described_class.unsubscribe_all }

  describe '.publish' do
    context 'when a subscriber raises' do
      let(:raising_callback) { ->(_event) { raise StandardError, 'subscriber blew up' } }

      before { described_class.subscribe(event_name, raising_callback) }

      it 'does not propagate the error to the publisher' do
        expect { described_class.publish(event_name, { case_id: SecureRandom.uuid }) }
          .not_to raise_error
      end

      it 'logs the error with the event name, so the failure is not silent' do
        allow(Rails.logger).to receive(:error)

        described_class.publish(event_name)

        expect(Rails.logger).to have_received(:error).with(/#{event_name}/)
      end

      it 'logs the underlying error message' do
        allow(Rails.logger).to receive(:error)

        described_class.publish(event_name)

        expect(Rails.logger).to have_received(:error).with(/subscriber blew up/)
      end

      # ActiveSupport::Notifications::Fanout guards each subscriber
      # individually, so this already holds — pinned because the boundary
      # rescue must not change it, and because it is the property that makes
      # rescuing at the boundary safe rather than lossy.
      it 'still runs the other subscribers for the same event' do
        other_ran = false
        described_class.subscribe(event_name, ->(_event) { other_ran = true })

        described_class.publish(event_name)

        expect(other_ran).to be(true)
      end

      # Fanout collects multiple subscriber errors into an
      # InstrumentationSubscriberError rather than re-raising one of them, so
      # the boundary rescue has to catch that too.
      it 'swallows the aggregate error when several subscribers raise' do
        described_class.subscribe(event_name, ->(_event) { raise StandardError, 'and again' })

        expect { described_class.publish(event_name) }.not_to raise_error
      end
    end

    context 'when a subscriber raises something that is not a StandardError' do
      # The boundary rescue is deliberately narrow. A deploy-time signal has to
      # keep terminating the process, which is the whole point of this work.
      [ Interrupt, NotImplementedError ].each do |error_class|
        it "propagates #{error_class} rather than swallowing it" do
          described_class.subscribe(event_name, ->(_event) { raise error_class })

          expect { described_class.publish(event_name) }.to raise_error(error_class)
        end
      end
    end

    context 'when no subscriber raises' do
      it 'delivers the event name and payload to the subscriber' do
        received = nil
        described_class.subscribe(event_name, ->(e) { received = e })
        payload = { case_id: SecureRandom.uuid }

        described_class.publish(event_name, payload)

        expect(received).to eq({ name: event_name, payload: payload })
      end

      it 'preserves symbol keys in the payload' do
        received = nil
        described_class.subscribe(event_name, ->(e) { received = e[:payload] })

        described_class.publish(event_name, { case_id: 'abc' })

        expect(received.keys).to eq([ :case_id ])
      end

      it 'publishes with an empty payload when none is given' do
        received = :unset
        described_class.subscribe(event_name, ->(e) { received = e[:payload] })

        described_class.publish(event_name)

        expect(received).to eq({})
      end
    end
  end

  # 6.1's check, asserted rather than argued: an error from a step must not
  # reject the record whose save published the event. This is the guard against
  # item 3.3a landing before Phase 3.
  describe 'a failing step during a domain write' do
    let(:business_process) { TestBusinessProcess }
    let(:start_step) { business_process.steps[business_process.start_step_name] }

    before do
      business_process.start_listening_for_events
      allow(start_step).to receive(:execute).and_raise(StandardError, 'start blew up')
    end

    after { business_process.stop_listening_for_events }

    it 'keeps the application form saved' do
      form = TestApplicationForm.new

      expect { form.save! }.not_to raise_error
      expect(form.reload).to be_persisted
    end

    # create_case_from_event saves the case, then start_from_event sets the step
    # and executes it. Rolling back only the step change would leave the case
    # row behind with no step — stuck in a different way, and not replayable,
    # because the start event's handler would create a second case on retry.
    # 6.2 names only transition_to_next_step, so this is an addition to the
    # plan's 1.1 scope rather than a restatement of it.
    it 'leaves no half-started case behind' do
      form = TestApplicationForm.create!

      expect(TestCase.where(application_form_id: form.id)).to be_empty
    end

    it 'logs the failure' do
      allow(Rails.logger).to receive(:error)

      TestApplicationForm.create!

      expect(Rails.logger).to have_received(:error).with(/start blew up/)
    end
  end
end
