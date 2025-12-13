class PaidLeaveApplication
  include ActiveModel::Model
  include Strata::Flows::ApplicationFormValidations

  validate_flow PaidLeaveFlow

  attr_accessor :id,
                :name,
                :date_of_birth,
                :employer_name,
                :leave_type

  validates :name, presence: true, on: Flow::NAME
  validates :date_of_birth, presence: true, on: Flow::DATE_OF_BIRTH
  validates :employer_name, presence: true, on: Flow::EMPLOYER_NAME
  validates :leave_type, presence: true, on: Flow::LEAVE_TYPE
end
