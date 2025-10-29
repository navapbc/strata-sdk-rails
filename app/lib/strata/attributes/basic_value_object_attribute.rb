# frozen_string_literal: true

module Strata
  module Attributes
    # Internal module used by other Strata attribute modules to implement attributes
    # whose type is a subclass of Strata::ValueObject. This module is not intended to be
    # used directly by clients of Strata.
    #
    # The module provides functionality to create attributes that represent complex values
    # as value objects, with nested attributes that are automatically mapped to and from
    # the value object's properties. For each value object attribute, it creates:
    #
    # - Individual attributes for each nested field (e.g., address_street, address_city)
    # - A getter method that constructs a value object from the nested attributes
    # - A setter method that accepts either a value object or a hash of values
    # - Automatic validation handling for the nested structure
    #
    # This module is used internally to implement higher-level attribute modules in Strata.
    module BasicValueObjectAttribute
      extend ActiveSupport::Concern
      include Strata::Validations

      class_methods do
        # Defines an attribute associated with a subclass of
        # Strata::ValueObject
        #
        # @param [Symbol] name The base name for the attribute
        # @param [Class] value_class the subclass of Strata::ValueObject
        # @param [Hash] options Options for the attribute
        # @return [void]
        # @param [Object] nested_attribute_types
        def basic_value_object_attribute(name, value_class, nested_attribute_types, options = {})
          # Define the base attribute with its subfields
          nested_attribute_types.each do |nested_attribute_name, nested_attribute_type|
            strata_attribute "#{name}_#{nested_attribute_name}", nested_attribute_type
          end

          # Define the getter method
          define_method(name) do
            value_hash = nested_attribute_types.keys.map do |nested_attribute_name|
              [ nested_attribute_name, send("#{name}_#{nested_attribute_name}") ]
            end.to_h
            return nil if value_hash.values.all?(&:nil?)
            value_class.new(value_hash)
          end

          # Define the setter method
          define_method(:"#{name}=") do |value|
            case value
            when value_class
              nested_attribute_types.keys.each do |nested_attribute_name|
                send("#{name}_#{nested_attribute_name}=", value.send(nested_attribute_name))
              end
            when Hash
              nested_attribute_types.keys.each do |nested_attribute_name|
                send("#{name}_#{nested_attribute_name}=", value[nested_attribute_name.to_sym] || value[nested_attribute_name.to_s])
              end
            # TODO: pass along _a_ value so we know there was some value that was attempted to be used
            else
              nested_attribute_types.keys.each do |nested_attribute_name|
                send("#{name}_#{nested_attribute_name}=", :invalid_value)
              end
            end
          end

          strata_validates_nested(name)
        end
      end
    end
  end
end
