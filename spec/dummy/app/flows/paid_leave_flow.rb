# Dummy paid leave flow
class PaidLeaveFlow
  include Strata::Flows::ApplicationFormFlow
  task :personal_information do
    question_page :name
    question_page :date_of_birth
  end
  task :employment_details do
    question_page :employer_name
  end
  task :leave_details do
    question_page :leave_type
  end
  end_page :review
end
