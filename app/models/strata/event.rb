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

    # Payloads are serialized when first read or saved, and raise if they break the contract.
    attribute :payload, Strata::Events::PayloadType.new

    validates :name, presence: true
    validates :published_at, presence: true

    def readonly?
      persisted?
    end
  end
end
