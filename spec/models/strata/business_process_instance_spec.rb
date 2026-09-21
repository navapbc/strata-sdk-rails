# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::BusinessProcessInstance do
  let(:kase) { create(:test_case) }
  let(:instance) { kase.business_process_instance }

  def event(name)
    { name:, payload: { case_id: kase.id } }
  end

  describe '#transition_to_next_step' do
    before { kase.update!(business_process_current_step: 'staff_task') }

    it 'returns :transitioned when a transition applies' do
      expect(instance.transition_to_next_step(event('event1'))).to eq(:transitioned)
    end

    it 'returns :no_match when no transition applies' do
      expect(instance.transition_to_next_step(event('event3'))).to eq(:no_match)
    end
  end

  describe '#start_from_event' do
    before { kase.update!(business_process_current_step: nil) }

    it 'returns :transitioned' do
      expect(instance.start_from_event(event('TestApplicationFormCreated'))).to eq(:transitioned)
    end
  end
end
