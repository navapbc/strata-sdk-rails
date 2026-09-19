# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::BusinessProcess do
  let(:application_form) { TestApplicationForm.new }
  let(:kase) { TestCase.find_by(application_form_id: application_form.id) }
  let(:business_process_instance) { kase.business_process_instance }
  let(:business_process) { TestBusinessProcess }

  before do
    business_process.start_listening_for_events
  end

  after do
    # Clean up any subscriptions to avoid side effects in other tests
    business_process.stop_listening_for_events
  end

  describe '#handle_event' do
    before do
      application_form.save!
    end

    it 'executes the complete process chain' do
      expect(kase.business_process_instance.current_step).to eq('staff_task')

      Strata::EventManager.publish('event1', { case_id: kase.id })
      # system_process automatically publishes event2
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('staff_task_2')

      Strata::EventManager.publish('event3', { case_id: kase.id })
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('applicant_task')

      Strata::EventManager.publish('event4', { case_id: kase.id })
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('third_party_task')

      Strata::EventManager.publish('event5', { case_id: kase.id })
      # system_process_2 automatically publishes event6
      kase.reload
      expect(kase).to be_closed
      expect(kase.business_process_instance.current_step).to eq('end')
    end

    context 'when no transition is defined for the event' do
      it 'maintains current step' do
        [ 'event2', 'event3', 'event4' ].each do |event|
          Strata::EventManager.publish(event, { case_id: kase.id })
        end
        expect(kase.business_process_instance.current_step).to eq('staff_task')
      end

      it 'does not re-execute the current step' do
        allow(Strata::TaskService.get).to receive(:create_task)
        [ 'event2', 'event3', 'event4' ].each do |event|
          Strata::EventManager.publish(event, { case_id: kase.id })
        end
        expect(Strata::TaskService.get).not_to have_received(:create_task)
      end
    end
  end

  # Covers Phase 1 item 1.3, per spec.md 6.4 and 5.6a. handle_event aggregates
  # over the cases the event resolved to, so the Phase 3 delivery job can tell
  # applied work from a no-op instead of filing every no-op as succeeded.
  describe '#handle_event return value' do
    let(:event) { { name: 'event1', payload: { case_id: kase.id } } }

    before { application_form.save! }

    # D9: the `private` above the second `class << self` block in
    # business_process.rb applies to instance methods, so it privatizes nothing
    # here. Pinned because the Phase 2 router calls these as public methods.
    it 'is a public class method, despite the private keyword above it' do
      expect(business_process).to respond_to(:handle_event)
      expect(business_process).to respond_to(:start_event?)
    end

    context 'when a case transitioned' do
      it 'returns :transitioned' do
        expect(business_process.handle_event(event)).to eq(:transitioned)
      end
    end

    context 'when the event matches a case but no transition applies' do
      it 'returns :no_match' do
        stale_event = { name: 'event3', payload: { case_id: kase.id } }

        expect(business_process.handle_event(stale_event)).to eq(:no_match)
      end

      it 'leaves the case where it was' do
        business_process.handle_event({ name: 'event3', payload: { case_id: kase.id } })

        expect(kase.reload.business_process_current_step).to eq('staff_task')
      end
    end

    # The case most worth seeing: a payload whose case_id matches nothing at
    # all. An empty for_event result is a no_match, not a vacuous success.
    context 'when the event matches no case' do
      it 'returns :no_match' do
        orphan_event = { name: 'event1', payload: { case_id: SecureRandom.uuid } }

        expect(business_process.handle_event(orphan_event)).to eq(:no_match)
      end
    end

    context 'when the event resolves to several cases' do
      let(:other_form) { TestApplicationForm.create! }
      let(:other_case) { TestCase.find_by(application_form_id: other_form.id) }

      it 'returns :transitioned when any one of them moved' do
        other_case.update!(business_process_current_step: 'applicant_task')
        allow(TestCase).to receive(:for_event).and_return(TestCase.where(id: [ kase.id, other_case.id ]))

        expect(business_process.handle_event(event)).to eq(:transitioned)
      end

      it 'returns :no_match when none of them moved' do
        kase.update!(business_process_current_step: 'applicant_task')
        other_case.update!(business_process_current_step: 'applicant_task')
        allow(TestCase).to receive(:for_event).and_return(TestCase.where(id: [ kase.id, other_case.id ]))

        expect(business_process.handle_event(event)).to eq(:no_match)
      end
    end

    context 'when the event is a start event' do
      it 'returns :transitioned' do
        new_form = TestApplicationForm.create!
        start_event = { name: 'TestApplicationFormCreated',
                        payload: { application_form_id: new_form.id } }

        expect(business_process.handle_event(start_event)).to eq(:transitioned)
      end
    end
  end

  describe '#stop_listening_for_events' do
    before do
      application_form.save!
    end

    it 'unsubscribes from all events' do
      business_process.stop_listening_for_events

      expect(kase.business_process_instance.current_step).to eq('staff_task')

      # Try publishing various events

      Strata::EventManager.publish('event1', { case_id: kase.id })
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('staff_task') # Should not change

      Strata::EventManager.publish('event2', { case_id: kase.id })
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('staff_task') # Should not change

      Strata::EventManager.publish('event3', { case_id: kase.id })
      kase.reload
      expect(kase.business_process_instance.current_step).to eq('staff_task') # Should not change
    end
  end
end
