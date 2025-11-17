class AddServiceIdsToTestRecords < ActiveRecord::Migration[8.0]
  def change
    add_column :test_records, :service_ids, :integer, array: true, default: []
  end
end
