# frozen_string_literal: true

FactoryBot.define do
  factory :sample_application_form do
    trait :submittable do
      applicant_name_first { Faker::Name.first_name }
      date_of_birth { Faker::Date.birthday(min_age: 18, max_age: 65) }
      employer_name { "My employer" }
      leave_type { "medical" }
    end
  end

  factory :sample_employment_detail do
    sample_application_form
    business_name { "Acme Corp" }
    role { "Engineer" }
  end
end
