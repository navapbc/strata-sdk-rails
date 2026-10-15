# frozen_string_literal: true

class CreateStrataEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :strata_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false

      # Plain JSON produced by Strata::Events::Payload.serialize
      t.jsonb :payload, null: false, default: {}

      # Optional polymorphic publisher (the record that published the event)
      t.references :publisher, polymorphic: true, type: :uuid

      t.datetime :published_at, null: false

      # Events are immutable: created_at only, no updated_at
      t.datetime :created_at, null: false
    end

    add_index :strata_events, [ :name, :published_at ]
    add_index :strata_events, :published_at

    create_table :strata_event_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :event, type: :uuid, null: false, index: false,
                           foreign_key: { to_table: :strata_events, on_delete: :cascade }

      # Stable subscriber key, such as "PassportBusinessProcess.handle_event"
      t.string :subscriber, null: false

      t.integer  :status, null: false, default: 0
      t.integer  :attempts, null: false, default: 0
      t.datetime :next_attempt_at
      t.datetime :enqueued_at
      # Class name only: error messages can contain PII
      t.string   :error_class
      t.datetime :completed_at

      t.timestamps
    end

    add_index :strata_event_deliveries, [ :event_id, :subscriber ], unique: true

    # Serves the stranded-attempt sweeper: due, unenqueued pending (0) and failed (2) deliveries
    add_index :strata_event_deliveries, :next_attempt_at,
              where: "status IN (0, 2) AND enqueued_at IS NULL",
              name: "index_strata_event_deliveries_on_sweep"
  end
end
