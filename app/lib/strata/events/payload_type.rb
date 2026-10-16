# frozen_string_literal: true

module Strata
  module Events
    # PayloadType is the attribute type for stored event payloads. It runs
    # payloads through {Payload.serialize} whenever Rails converts them for the
    # database, so assigned payloads, payloads changed in place, and query
    # values all follow the payload contract. Checking is lazy: a bad payload
    # raises {Payload::InvalidPayloadError} when the payload is first read or
    # saved, not when it is assigned, and valid? does not check it.
    #
    # @example
    #   attribute :payload, Strata::Events::PayloadType.new
    #
    class PayloadType < ActiveRecord::Type::Json
      # Rails' JSON cast also goes through serialize, so assigned payloads are
      # checked when first read, as well as when saved.
      def serialize(value)
        super(Payload.serialize(value))
      end
    end
  end
end
