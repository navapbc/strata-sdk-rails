# frozen_string_literal: true

# Dummy sample flow
class SampleFlow
  include Strata::Flows::ApplicationFormFlow
  task :personal_information do
    question_page :name, fields: [ :applicant_name_first ]
    question_page :date_of_birth, fields: [
      date_of_birth: [ :month, :day, :year ]
    ]
  end
  task :employment_details, depends_on: [ :personal_information ] do
    question_page :employer_name
  end
  task :prior_employment, depends_on: [ :employment_details ] do
    loop :prior_employer, association: :sample_employment_details do
      question_page :business_name
      question_page :role
    end
  end
  task :leave_details, depends_on: [ :prior_employment ] do
    question_page :leave_type
  end
  end_page :review
end
