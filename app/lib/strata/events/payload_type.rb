# frozen_string_literal: true

module Strata
  module Events
    # PayloadType is the attribute type for stored event payloads. It runs
    # assigned payloads through {Payload.serialize} before jsonb converts them
    # to JSON, so a record or Ruby time can't slip into stored JSON. Rails
    # casts lazily, so a bad payload raises when it is first read or saved.
    # Payloads read from the database are not checked again.
    #
    # @example
    #   attribute :payload, Strata::Events::PayloadType.new
    #
    class PayloadType < ActiveRecord::Type::Json
      # @raise [Payload::InvalidPayloadError] for payloads that break the payload contract
      def cast(value)
        super(Payload.serialize(value))
      end
    end
  end
end
