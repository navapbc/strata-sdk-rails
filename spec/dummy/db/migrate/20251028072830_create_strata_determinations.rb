# frozen_string_literal: true

class CreateStrataDeterminations < ActiveRecord::Migration[8.0]
  def change
    create_table :strata_determinations, id: :uuid do |t|
      # Polymorphic association - can belong to ANY aggregate root
      t.uuid :subject_id, null: false
      t.string :subject_type, null: false

      # Determination specifics
      t.string :decision_method, null: false
      t.string :reason, null: false
      t.string :outcome, null: false

      # Payload
      t.jsonb :determination_data, null: false, default: {}

      # Audit trail
      t.uuid :determined_by_id # If nil, means determined by automated process
      t.datetime :determined_at, null: false

      t.datetime :created_at, null: false
    end

    add_index :strata_determinations, [ :subject_id, :subject_type ],
              name: 'index_strata_determinations_on_polymorphic_subject'

    add_index :strata_determinations, :determined_by_id
    add_index :strata_determinations, :determined_at
    add_index :strata_determinations, :created_at
  end
end
