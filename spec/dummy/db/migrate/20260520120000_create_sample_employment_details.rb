# frozen_string_literal: true

class CreateSampleEmploymentDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :sample_employment_details do |t|
      t.references :sample_application_form, foreign_key: true
      t.string :business_name
      t.string :role
      t.timestamps
    end
  end
end
