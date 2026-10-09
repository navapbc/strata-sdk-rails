# frozen_string_literal: true

class AddClaimUserFacingIdSequenceToTestRecords < ActiveRecord::Migration[8.0]
  def up
    add_column :test_records, :claim_user_facing_id_sequence, :bigserial, null: false
    add_index :test_records, :claim_user_facing_id_sequence, unique: true
  end

  def down
    remove_index :test_records, :claim_user_facing_id_sequence
    remove_column :test_records, :claim_user_facing_id_sequence
  end
end
