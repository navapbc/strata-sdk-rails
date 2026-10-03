# frozen_string_literal: true

module Strata
  # Attributes is a module that extends ActiveRecord with custom attribute types.
  # It provides a consistent interface for defining specialized attributes like
  # memorable dates, names, addresses, tax IDs, and money amounts.
  #
  # This module should be included in models that need these custom attribute types.
  # See app/lib/strata/attributes/ folder for the list of all available strata attributes.
  #
  # @example Including Attributes in a model
  #   class MyModel < ApplicationRecord
  #     include Strata::Attributes
  #
  #     strata_attribute :birth_date, :memorable_date
  #     strata_attribute :applicant_name, :name
  #     strata_attribute :salary, :money
  #   end
  #
  module Attributes
    extend ActiveSupport::Concern
    include Strata::Attributes::AddressAttribute
    include Strata::Attributes::ArrayAttribute
    include Strata::Attributes::MemorableDateAttribute
    include Strata::Attributes::MoneyAttribute
    include Strata::Attributes::NameAttribute
    include Strata::Attributes::RangeAttribute
    include Strata::Attributes::TaxIdAttribute
    include Strata::Attributes::USDateAttribute
    include Strata::Attributes::UserFacingIdAttribute
    include Strata::Attributes::YearMonthAttribute
    include Strata::Attributes::YearQuarterAttribute

    # Helper method. Given a type, return the corresponding class in the Strata module.
    # If the class is not found in the Strata module, it will try to find it
    # in the Strata module, then in the global namespace.
    def self.resolve_class(type)
      begin
        "Strata::#{type.to_s.camelize}".constantize
      rescue NameError
        type.to_s.camelize.constantize
      end
    end

    class_methods do
      # Returns the registry of strata attributes defined on this model.
      # Each entry maps the attribute name to its expanded parameter keys.
      #
      # @return [Hash{Symbol => Array<Symbol, Hash>}]
      #
      # @example
      #   { applicant_name: [
      #       :applicant_name_first,
      #       :applicant_name_middle,
      #       :applicant_name_last,
      #       :applicant_name_suffix
      #   ]}
      def strata_attributes_registry
        @strata_attributes_registry ||= {}
      end

      # Defines a custom attribute with the specified type.
      #
      # @param [Symbol] name The name of the attribute
      # @param [Symbol] type The type of attribute (:address, :memorable_date, :money, :name, :tax_id, :us_date, :year_quarter)
      # @param [Hash] options Options for the attribute. This includes:
      #   - `:array` (Boolean): If true, the attribute will be an array of the specified type
      #   - `:range` (Boolean): If true, the attribute will be a Strata::ValueRange of the specified type
      # @raise [ArgumentError] If an unsupported attribute type is provided
      # @return [void]
      def strata_attribute(name, type, options = {})
        is_array = options.delete(:array) || false
        is_range = options.delete(:range) || false

        if is_array
          array_attribute name, type, options
          return
        end

        if is_range
          range_attribute name, type, options
          return
        end

        if respond_to?("#{type}_attribute")
          send("#{type}_attribute", name, options)
        else
          # Fall back to ActiveModel::Attributes
          attribute name, type, **options
        end
      end
    end
  end
end
