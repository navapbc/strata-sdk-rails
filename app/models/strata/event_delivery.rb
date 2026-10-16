# frozen_string_literal: true

module Strata
  # EventDelivery tracks delivering one {Strata::Event} to one durable
  # subscriber: its status, attempts, retry schedule, and the class name of its
  # latest error. Error messages are not stored because they can contain PII.
  #
  # See docs/specs/durable-events/spec.md#strata_event_deliveries.
  class EventDelivery < ApplicationRecord
    self.table_name = "strata_event_deliveries"

    belongs_to :event, class_name: "Strata::Event", inverse_of: :deliveries

    # The sweep index's partial condition lists the pending and failed values.
    enum :status, { pending: 0, succeeded: 1, failed: 2, no_match: 3, dead: 4 }, validate: true

    # One delivery per subscriber for an event is enforced by a unique index.
    validates :subscriber, presence: true
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
