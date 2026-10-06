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

  describe 'handler outcome' do
    before do
      application_form.save!
    end

    context 'when the event starts a business process' do
      it 'creates and starts a case and reports :transitioned' do
        event = { name: 'TestApplicationFormCreated', payload: { application_form_id: application_form.id } }

        expect { expect(business_process.handle_event(event)).to eq(:transitioned) }
          .to change { TestCase.where(application_form_id: application_form.id).count }.by(1)
      end
    end

    context 'when the event moves the resolved case' do
      it 'reports :transitioned' do
        kase.update!(business_process_current_step: 'staff_task_2')
        expect(business_process.handle_event({ name: 'event3', payload: { case_id: kase.id } })).to eq(:transitioned)
        expect(kase.reload.business_process_instance.current_step).to eq('applicant_task')
      end
    end

    context 'when no resolved case has a transition for the event' do
      it 'reports :no_match and leaves the case on its current step' do
        expect(business_process.handle_event({ name: 'event4', payload: { case_id: kase.id } })).to eq(:no_match)
        expect(kase.reload.business_process_instance.current_step).to eq('staff_task')
      end
    end

    context 'when the event resolves to no cases' do
      it 'reports :no_match' do
        expect(business_process.handle_event({ name: 'event1', payload: { case_id: SecureRandom.uuid } })).to eq(:no_match)
      end
    end

    context 'when the event resolves to several cases and only some move' do
      let!(:other_case) do
        TestCase.create!(application_form_id: application_form.id, business_process_current_step: 'staff_task_2')
      end

      it 'reports :transitioned and moves only the matching case' do
        event = { name: 'event3', payload: { application_form_id: application_form.id } }

        expect(business_process.handle_event(event)).to eq(:transitioned)
        expect(other_case.reload.business_process_instance.current_step).to eq('applicant_task')
        expect(kase.reload.business_process_instance.current_step).to eq('staff_task')
      end
    end
  end

  describe 'per-case outcome log' do
    def outcome_line(event_name, case_id, outcome)
      "strata.business_process.outcome event=#{event_name} subscriber=TestBusinessProcess.handle_event " \
        "case_type=TestCase case_id=#{case_id} outcome=#{outcome}"
    end

    def outcome_lines
      lines = []
      allow(Rails.logger).to receive(:info).and_call_original
      allow(Rails.logger).to receive(:info).with(a_string_starting_with('strata.business_process.outcome')) { |line| lines << line }
      yield
      lines
    end

    context 'when the event starts a business process' do
      it 'logs :transitioned for the created case' do
        lines = outcome_lines { application_form.save! }

        expect(lines).to eq([ outcome_line('TestApplicationFormCreated', kase.id, 'transitioned') ])
      end
    end

    context 'when the event moves the resolved case' do
      it 'logs :transitioned for that case' do
        application_form.save!
        kase.update!(business_process_current_step: 'staff_task_2')

        lines = outcome_lines { business_process.handle_event({ name: 'event3', payload: { case_id: kase.id } }) }

        expect(lines).to eq([ outcome_line('event3', kase.id, 'transitioned') ])
      end
    end

    context 'when the resolved case has no transition for the event' do
      it 'logs :no_match for that case' do
        application_form.save!

        lines = outcome_lines { business_process.handle_event({ name: 'event4', payload: { case_id: kase.id } }) }

        expect(lines).to eq([ outcome_line('event4', kase.id, 'no_match') ])
      end
    end

    context 'when the event resolves to no cases' do
      it 'logs nothing' do
        lines = outcome_lines { business_process.handle_event({ name: 'event1', payload: { case_id: SecureRandom.uuid } }) }

        expect(lines).to be_empty
      end
    end

    context 'when the event resolves to several cases and only some move' do
      it 'logs one outcome per resolved case' do
        application_form.save!
        other_case = TestCase.create!(application_form_id: application_form.id, business_process_current_step: 'staff_task_2')

        lines = outcome_lines do
          business_process.handle_event({ name: 'event3', payload: { application_form_id: application_form.id } })
        end

        expect(lines).to contain_exactly(
          outcome_line('event3', kase.id, 'no_match'),
          outcome_line('event3', other_case.id, 'transitioned')
        )
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
