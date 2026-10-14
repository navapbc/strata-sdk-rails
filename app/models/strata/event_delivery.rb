# frozen_string_literal: true

module Strata
  # EventDelivery tracks delivering one {Strata::Event} to one durable
  # subscriber: its status, attempts, retry schedule, and latest error.
  #
  # See docs/specs/durable-events/spec.md#strata_event_deliveries.
  class EventDelivery < ApplicationRecord
    self.table_name = "strata_event_deliveries"

    # Error messages can contain personal data, so only a bounded prefix is kept.
    LAST_ERROR_LIMIT = 1_000

    belongs_to :event, class_name: "Strata::Event", inverse_of: :deliveries

    enum :status, pending: 0, succeeded: 1, failed: 2, no_match: 3, dead: 4

    normalizes :last_error, with: ->(error) { error.truncate(LAST_ERROR_LIMIT) }

    validates :subscriber, presence: true, uniqueness: { scope: :event_id }
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
