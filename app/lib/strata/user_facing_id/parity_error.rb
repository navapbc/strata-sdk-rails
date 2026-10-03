# frozen_string_literal: true

module Strata
  module UserFacingId
    # Raised when a user-facing ID checksum does not match its data bits.
    class ParityError < Error; end
  end
end
