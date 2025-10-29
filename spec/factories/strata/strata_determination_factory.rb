# frozen_string_literal: true

FactoryBot.define do
  factory :strata_determination, class: 'Strata::Determination' do
    association :subject, factory: :test_application_form
    decision_method { :automated }
    reason { "age_under_19" }
    outcome { :automated_exemption }
    determination_data { { date_of_birth: "placeholder", evaluated_on: "placeholder" } }
    determined_by_id { nil }
    determined_at { Date.new(2025, 01, 15).in_time_zone('America/Chicago') }
  end
end
