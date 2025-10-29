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

    # Query scopes for filtering determinations

    # Subject-based scopes
    scope :for_subject, ->(subject) { where(subject: subject) }
    scope :for_subjects, ->(subjects) { where(subject: Array(subjects)) }
    scope :for_subject_type, lambda { |type|
      type_name = type.is_a?(Class) ? type.name : type.to_s
      where(subject_type: type_name)
    }
    scope :for_subject_id, lambda { |id, type = nil|
      scope = where(subject_id: id)
      scope = scope.where(subject_type: type.is_a?(Class) ? type.name : type.to_s) if type.present?
      scope
    }

    # Decision method, reason, and outcome scopes
    scope :with_decision_method, lambda { |method_or_methods|
      methods = Array(method_or_methods).map(&:to_s)
      where(decision_method: methods)
    }
    scope :with_reason, lambda { |reason_or_reasons|
      reasons = Array(reason_or_reasons).map(&:to_s)
      where(reason: reasons)
    }
    scope :with_outcome, lambda { |outcome_or_outcomes|
      outcomes = Array(outcome_or_outcomes).map(&:to_s)
      where(outcome: outcomes)
    }

    # User determination scope
    scope :determined_by, ->(user_id) { where(determined_by_id: user_id) }

    # Time window scopes
    scope :determined_before, ->(time) { where(arel_table[:determined_at].lt(time)) }
    scope :determined_after, ->(time) { where(arel_table[:determined_at].gt(time)) }
    scope :determined_between, ->(start_time, end_time) { where(determined_at: start_time..end_time) }

    # Ordering scopes
    scope :latest_first, -> { order(determined_at: :desc) }
    scope :oldest_first, -> { order(determined_at: :asc) }
  end
end
