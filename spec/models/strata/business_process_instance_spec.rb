# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::BusinessProcessInstance do
  let(:kase) { TestCase.create!(business_process_current_step: current_step) }
  let(:business_process_instance) { kase.business_process_instance }

  describe '#transition_to_next_step' do
    context 'when the event has a transition from the current step' do
      let(:current_step) { 'staff_task_2' }

      it 'moves the case to the next step and reports :transitioned' do
        expect(business_process_instance.transition_to_next_step({ name: 'event3', payload: { case_id: kase.id } }))
          .to eq(:transitioned)
        expect(kase.reload.business_process_instance.current_step).to eq('applicant_task')
      end
    end

    context 'when the transition leads to the end of the process' do
      let(:current_step) { 'system_process_2' }

      it 'closes the case and reports :transitioned' do
        expect(business_process_instance.transition_to_next_step({ name: 'event6', payload: { case_id: kase.id } }))
          .to eq(:transitioned)
        expect(kase.reload).to be_closed
      end
    end

    context 'when the event has no transition from the current step' do
      let(:current_step) { 'staff_task' }

      it 'leaves the case on its current step and reports :no_match' do
        expect(business_process_instance.transition_to_next_step({ name: 'event4', payload: { case_id: kase.id } }))
          .to eq(:no_match)
        expect(kase.reload.business_process_instance.current_step).to eq('staff_task')
      end
    end

    context 'when the next step raises' do
      let(:current_step) { 'applicant_task' }

      before do
        allow(TestBusinessProcess.get_step('third_party_task')).to receive(:execute).and_raise(StandardError, 'boom')
      end

      # The case has already advanced when the step fails; making step mutation and
      # execution atomic is a separate change in the durable events plan.
      it 'still reports :transitioned' do
        expect(business_process_instance.transition_to_next_step({ name: 'event4', payload: { case_id: kase.id } }))
          .to eq(:transitioned)
      end
    end
  end
end
