# frozen_string_literal: true

module Strata
  # Determinable concern provides determination recording capability to any model.
  # By default, this is included in Strata::ApplicationForm.
  # Include this module in other models to add a has_many :determinations association
  # and the record_determination! convenience method.
  #
  # @example Using determinations on an ApplicationForm
  #   my_form = MyApplicationForm.new
  #   my_form.record_determination!(
  #     decision_method: :automated,
  #     reasons: ["pregnant_member"],
  #     outcome: :automated_exemption,
  #     determined_at: Date.today,
  #     determination_data: ruleset.output_data.reasons
  #   )
  #
  # @example Including Determinable in another model
  #   class MyCustomModel < ApplicationRecord
  #     include Strata::Determinable
  #   end
  module Determinable
    extend ActiveSupport::Concern

    included do
      has_many :determinations, as: :subject, class_name: "Strata::Determination", dependent: :destroy
    end

    # Create a determination with method, reason, and outcome.
    #
    # @param decision_method [String, Symbol] How the determination was made
    #   (attestation, automated, staff_review)
    # @param reasons [Array<String>] Why this determination was made
    #   (e.g., pregnant_member, incarcerated, requirements_verification)
    # @param outcome [String, Symbol] Result of determination
    #   (e.g., automated_exemption, requirements_met, requirements_not_met)
    # @param determination_data [Hash] Result from Rules::Engine or other data
    # @param determined_at [Time] The date and time the determination takes place
    # @param determined_by_id [String, UUID] UUID of user who made the determination
    #   (nil if automated)
    #
    # @return [Strata::Determination] The created determination record
    # @raise [ActiveRecord::RecordInvalid] If the record fails validation
    def record_determination!(decision_method:, reasons:, outcome:, determination_data:, determined_at:, determined_by_id: nil)
      determinations.create!(
        decision_method:,
        reasons:,
        outcome:,
        determination_data:,
        determined_at:,
        determined_by_id:
      )
    end
  end
end
