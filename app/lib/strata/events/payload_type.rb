# frozen_string_literal: true

module Strata
  module Events
    # PayloadType is the attribute type for stored event payloads. It runs
    # payloads through {Payload.serialize} whenever Rails converts them for the
    # database, so assigned payloads, payloads changed in place, and query
    # values all follow the payload contract. A bad payload raises
    # {Payload::InvalidPayloadError} before it is saved.
    #
    # @example
    #   attribute :payload, Strata::Events::PayloadType.new
    #
    class PayloadType < ActiveRecord::Type::Json
      # Rails' JSON cast also goes through serialize, so this covers assignment too.
      def serialize(value)
        super(Payload.serialize(value))
      end
    end
  end
end
