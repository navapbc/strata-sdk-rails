# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strata::Attributes do
  let(:object) { TestRecord.new }

  describe ".strata_attributes_registry" do
    it "tracks multi-column strata attributes with their expanded fields" do
      registry = TestRecord.strata_attributes_registry

      expect(registry[:name]).to eq([ :name_first, :name_middle, :name_last, :name_suffix ])
      expect(registry[:address]).to eq([
        :address_street_line_1, :address_street_line_2,
        :address_city, :address_state, :address_zip_code
      ])
      expect(registry[:period]).to eq([ :period_start, :period_end ])
      expect(registry[:base_period]).to eq([ :base_period_start, :base_period_end ])
      expect(registry[:date_of_birth]).to eq([ { date_of_birth: [ :month, :day, :year ] } ])
    end

    it "does not register single-column strata attributes" do
      registry = TestRecord.strata_attributes_registry

      expect(registry).not_to have_key(:weekly_wage)
      expect(registry).not_to have_key(:tax_id)
      expect(registry).not_to have_key(:user_facing_id)
      expect(registry).not_to have_key(:adopted_on)
      expect(registry).not_to have_key(:reporting_period)
      expect(registry).not_to have_key(:activity_reporting_period)
    end

    it "does not register array strata attributes" do
      registry = TestRecord.strata_attributes_registry

      expect(registry).not_to have_key(:addresses)
      expect(registry).not_to have_key(:names)
      expect(registry).not_to have_key(:leave_periods)
    end
  end

  describe "persisting and loading from database" do
    it "preserves all attributes when saving and loading multiple value objects" do
      name = build(:name, :with_middle)
      address = build(:address, :base, :with_street_line_2)
      object.name = name
      object.address = address
      object.tax_id = Strata::TaxId.new("987-65-4321")
      object.weekly_wage = Strata::Money.new(cents: 5000)
      object.date_of_birth = Strata::USDate.new(1990, 3, 15)
      object.period = Strata::DateRange.new(start: Strata::USDate.new(2023, 1, 1), end: Strata::USDate.new(2023, 12, 31))
      object.save!

      loaded_record = TestRecord.find(object.id)

      # Verify name
      expect(loaded_record.name).to eq(name)
      expect(loaded_record.name_first).to eq(name.first)
      expect(loaded_record.name_middle).to eq(name.middle)
      expect(loaded_record.name_last).to eq(name.last)

      # Verify address
      expect(loaded_record.address).to eq(address)
      expect(loaded_record.address_street_line_1).to eq(address.street_line_1)
      expect(loaded_record.address_street_line_2).to eq(address.street_line_2)
      expect(loaded_record.address_city).to eq(address.city)
      expect(loaded_record.address_state).to eq(address.state)
      expect(loaded_record.address_zip_code).to eq(address.zip_code)

      # Verify tax_id
      expect(loaded_record.tax_id).to eq(Strata::TaxId.new("987-65-4321"))
      expect(loaded_record.tax_id.formatted).to eq("987-65-4321")

      # Verify money
      expect(loaded_record.weekly_wage).to eq(Strata::Money.new(cents: 5000))
      expect(loaded_record.weekly_wage.cents_amount).to eq(5000)
      expect(loaded_record.weekly_wage.dollar_amount).to eq(50.0)

      # Verify date_of_birth
      expect(loaded_record.date_of_birth).to eq(Strata::USDate.new(1990, 3, 15))

      # Verify date_range
      expect(loaded_record.period).to eq(Strata::DateRange.new(start: Strata::USDate.new(2023, 1, 1), end: Strata::USDate.new(2023, 12, 31)))
      expect(loaded_record.period_start).to eq(Strata::USDate.new(2023, 1, 1))
      expect(loaded_record.period_end).to eq(Strata::USDate.new(2023, 12, 31))
    end
  end
end
