# frozen_string_literal: true

class UserFacingIdsController < ApplicationController
  SAMPLE_RECORD_COUNT = 8

  def index
    @test_records = SAMPLE_RECORD_COUNT.times.map do |index|
      sequence = index + 1
      TestRecord.new(
        user_facing_id_sequence: sequence,
        claim_user_facing_id_sequence: sequence
      )
    end
  end
end
