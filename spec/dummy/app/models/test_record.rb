# frozen_string_literal: true

class TestRecord < ApplicationRecord
  include Strata::Attributes

  strata_attribute :address, :address
  strata_attribute :date_of_birth, :memorable_date
  strata_attribute :weekly_wage, :money
  strata_attribute :name, :name
  strata_attribute :adopted_on, :us_date
  strata_attribute :period, :us_date, range: true
  strata_attribute :tax_id, :tax_id
  strata_attribute :reporting_period, :year_quarter
  strata_attribute :base_period, :year_quarter, range: true
  strata_attribute :activity_reporting_period, :year_month

  # Array types
  strata_attribute :addresses, :address, array: true
  strata_attribute :leave_periods, [ :us_date, range: true ], array: true
  strata_attribute :names, :name, array: true
  strata_attribute :reporting_periods, :year_quarter, array: true
  strata_attribute :activity_reporting_periods, :year_month, array: true

  # Simple array attribute for collection_checkboxes preview
  attribute :service_ids, default: []
end
