# frozen_string_literal: true

require 'rails_helper'

# Covers Phase 1 items 1.1 (atomic step change and execution) and 1.3 (report an
# outcome), per spec.md 6.1, 6.2, 6.4 and 5.6a.
#
# Events are driven directly against the instance rather than published, so these
# specs exercise transitions and step execution without depending on whether any
# business process happens to be subscribed.
RSpec.describe Strata::BusinessProcessInstance do
  let(:business_process) { TestBusinessProcess }
  let(:kase) { create(:test_case) }
  let(:instance) { kase.business_process_instance }

  def event(name)
    { name: name, payload: { case_id: kase.id } }
  end

  before { kase.update!(business_process_current_step: 'staff_task') }

  describe '#transition_to_next_step' do
    context 'when a transition matches the current step' do
      it 'returns :transitioned' do
        expect(instance.transition_to_next_step(event('event1'))).to eq(:transitioned)
      end

      it 'persists the new step' do
        instance.transition_to_next_step(event('event1'))

        expect(kase.reload.business_process_current_step).to eq('system_process')
      end

      it 'executes the step it advanced to' do
        step = business_process.steps['system_process']
        allow(step).to receive(:execute).and_call_original

        instance.transition_to_next_step(event('event1'))

        expect(step).to have_received(:execute).with(kase)
      end
    end

    context 'when no transition matches the current step' do
      # Every event TestBusinessProcess defines except event1, which is the only
      # transition out of staff_task, plus an event it has never heard of.
      [ 'event2', 'event3', 'event4', 'event5', 'event6', 'NeverDefined' ].each do |event_name|
        it "returns :no_match for #{event_name}" do
          expect(instance.transition_to_next_step(event(event_name))).to eq(:no_match)
        end
      end

      it 'leaves the current step untouched' do
        instance.transition_to_next_step(event('event3'))

        expect(kase.reload.business_process_current_step).to eq('staff_task')
      end

      it 'executes no step at all' do
        business_process.steps.each_value { |step| allow(step).to receive(:execute) }

        instance.transition_to_next_step(event('event3'))

        business_process.steps.each_value do |step|
          expect(step).not_to have_received(:execute)
        end
      end
    end

    context 'when the step it advances to raises' do
      let(:failing_step) { business_process.steps['system_process'] }

      before do
        allow(failing_step).to receive(:execute).and_raise(StandardError, 'step blew up')
      end

      it 'propagates the error to the caller' do
        expect {
          instance.transition_to_next_step(event('event1'))
        }.to raise_error(StandardError, 'step blew up')
      end

      it 'logs the error before re-raising it' do
        allow(Rails.logger).to receive(:error)

        expect { instance.transition_to_next_step(event('event1')) }.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error).with(/step blew up/)
      end

      it 'rolls the step change back, so the case is not falsely advanced' do
        expect { instance.transition_to_next_step(event('event1')) }.to raise_error(StandardError)

        expect(kase.reload.business_process_current_step).to eq('staff_task')
      end

      # This is the defect in 6.2, and the reason durability alone does not fix
      # it: with the step saved before it runs, a retry computes its next step
      # from the already-advanced step, matches nothing, and no-ops. The case is
      # then permanently stuck and retrying re-confirms the stuck state.
      it 'leaves the event replayable, so a retry applies the transition' do
        expect { instance.transition_to_next_step(event('event1')) }.to raise_error(StandardError)

        allow(failing_step).to receive(:execute).and_return(nil)
        retried = kase.reload.business_process_instance.transition_to_next_step(event('event1'))

        expect(retried).to eq(:transitioned)
        expect(kase.reload.business_process_current_step).to eq('system_process')
      end
    end

    # rescue Exception currently absorbs these, so a step resists Ctrl-C and
    # swallows the very deploy-time termination signal this work exists to
    # survive. Neither is a StandardError, so neither should be logged and
    # re-raised — they should never be caught in the first place.
    context 'when the step raises something that is not a StandardError' do
      [ Interrupt, NotImplementedError ].each do |error_class|
        context "when it raises #{error_class}" do
          before do
            allow(business_process.steps['system_process']).to receive(:execute).and_raise(error_class)
          end

          it 'propagates it' do
            expect {
              instance.transition_to_next_step(event('event1'))
            }.to raise_error(error_class)
          end

          it 'still rolls the step change back' do
            expect { instance.transition_to_next_step(event('event1')) }.to raise_error(error_class)

            expect(kase.reload.business_process_current_step).to eq('staff_task')
          end
        end
      end
    end

    context 'when the transition leads to the end step' do
      before { kase.update!(business_process_current_step: 'system_process_2') }

      it 'closes the case and records the end step' do
        expect(instance.transition_to_next_step(event('event6'))).to eq(:transitioned)

        expect(kase.reload).to be_closed
        expect(kase.reload.business_process_current_step).to eq('end')
      end
    end
  end

  describe '#start_from_event' do
    let(:start_step) { business_process.steps[business_process.start_step_name] }

    before { kase.update!(business_process_current_step: nil) }

    it 'sets the start step and returns :transitioned' do
      expect(instance.start_from_event(event('TestApplicationFormCreated'))).to eq(:transitioned)

      expect(kase.reload.business_process_current_step).to eq(business_process.start_step_name)
    end

    it 'executes the start step' do
      allow(start_step).to receive(:execute).and_call_original

      instance.start_from_event(event('TestApplicationFormCreated'))

      expect(start_step).to have_received(:execute).with(kase)
    end

    # start_from_event has the same save-then-execute shape as
    # transition_to_next_step, so it needs the same treatment. 6.2 names only
    # transition_to_next_step; this asserts the fix covers both.
    context 'when the start step raises' do
      before { allow(start_step).to receive(:execute).and_raise(StandardError, 'start blew up') }

      it 'propagates the error' do
        expect {
          instance.start_from_event(event('TestApplicationFormCreated'))
        }.to raise_error(StandardError, 'start blew up')
      end

      it 'rolls the start step back' do
        expect {
          instance.start_from_event(event('TestApplicationFormCreated'))
        }.to raise_error(StandardError)

        expect(kase.reload.business_process_current_step).to be_nil
      end
    end
  end
end
