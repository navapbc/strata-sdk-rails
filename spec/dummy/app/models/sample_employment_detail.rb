# frozen_string_literal: true

class SampleEmploymentDetail < ApplicationRecord
  belongs_to :sample_application_form

  validates :business_name, presence: true, on: :business_name
  validates :role, presence: true, on: :role
end
