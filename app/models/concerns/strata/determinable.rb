# frozen_string_literal: true

module Strata
  # Determinable concern provides determination recording capability to any model.
  # Include this module to add a has_many :determinations association and the
  # record_determination! convenience method.
  #
  # @example Including Determinable in a model
  #   class MyCertificationCase < Strata::Case
  #     include Strata::Determinable
  #   end
  #
  # @example Recording a determination
  #   case.record_determination!(
  #     decision_method: :automated,
  #     reason: "pregnant_member",
  #     outcome: :automated_exemption,
  #     determination_data: ruleset.output_data.reasons
  #   )
  module Determinable
    extend ActiveSupport::Concern

    included do
      has_many :determinations, as: :subject, class_name: "Strata::Determination", dependent: :destroy
    end

    # Create a determination with method, reason, and outcome.
    #
    # @param decision_method [String, Symbol] How the determination was made
    #   (attestation, automated, staff_review)
    # @param reason [String] Why this determination was made
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
    def record_determination!(decision_method:, reason:, outcome:, determination_data:, determined_at:, determined_by_id: nil)
      determinations.create!(
        decision_method:,
        reason:,
        outcome:,
        determination_data:,
        determined_at:,
        determined_by_id:
      )
    end
  end
end
