# frozen_string_literal: true

FactoryBot.define do
  factory :strata_event, class: 'Strata::Event' do
    name { 'TestEventHappened' }
    payload { { 'case_id' => SecureRandom.uuid } }
  end

  factory :strata_event_delivery, class: 'Strata::EventDelivery' do
    association :event, factory: :strata_event
    subscriber { 'TestBusinessProcess.handle_event' }
  end
end
