# frozen_string_literal: true

module Strata
  # Event is an immutable record of a published event and its payload. Each
  # durable subscriber gets one {Strata::EventDelivery} that tracks delivering
  # the event to it. Once persisted, events are read-only; pruning deletes them
  # in SQL, and the database removes their deliveries.
  #
  # See docs/specs/durable-events/spec.md#data-model.
  #
  # @example Inspecting an event's deliveries
  #   Strata::Event.find(id).deliveries.map(&:status)
  class Event < ApplicationRecord
    self.table_name = "strata_events"

    has_many :deliveries, class_name: "Strata::EventDelivery", inverse_of: :event
    belongs_to :publisher, polymorphic: true, optional: true

    validates :name, presence: true
    validates :published_at, presence: true
    validate :payload_is_serialized, if: :payload_changed?

    def readonly?
      persisted?
    end

    private

    # Payloads are stored exactly as Strata::Events::Payload.serialize returns them.
    # The jsonb type converts any value to JSON on assignment, so this checks the
    # value as assigned, before that conversion hides records and Ruby times.
    def payload_is_serialized
      assigned = payload_before_type_cast
      return if Strata::Events::Payload.serialize(assigned) == assigned

      errors.add(:payload, "must be serialized with Strata::Events::Payload.serialize")
    rescue Strata::Events::Payload::InvalidPayloadError => e
      errors.add(:payload, e.message)
    end
  end
end
