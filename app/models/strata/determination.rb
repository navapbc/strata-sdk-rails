# frozen_string_literal: true

module Strata
  # Determination represents a decision or outcome recorded for an aggregate root.
  # It supports polymorphic associations, allowing any aggregate root to have determinations.
  #
  # Determinations can be created through:
  # - Automated processes (decision_method: :automated, determined_by_id: nil)
  # - Staff review (decision_method: :staff_review, determined_by_id: staff_uuid)
  # - User attestation (decision_method: :attestation, determined_by_id: user_uuid)
  #
  # @example Recording an automated determination
  #   record.record_determination!(
  #     decision_method: :automated,
  #     reason: "pregnant_member",
  #     outcome: :automated_exemption,
  #     determination_data: RulesEngine.new.evaluate(:pregnant_member).reasons
  #   )
  #
  # @example Recording a staff-reviewed determination
  #   record.record_determination!(
  #     decision_method: :staff_review,
  #     reason: "requirements_verification",
  #     outcome: :requirements_met,
  #     determination_data: RulesEngine.new.evaluate(:requirements_verification).reasons
  #     determined_by_id: staff_uuid
  #   )
  class Determination < ApplicationRecord
    self.table_name = "strata_determinations"

    # Polymorphic association to any aggregate root
    belongs_to :subject, polymorphic: true, optional: false

    # Validations
    validates :decision_method, :reason, :outcome, :determination_data, :determined_at, presence: true
  end
end
