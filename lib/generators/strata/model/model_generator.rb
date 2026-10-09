# frozen_string_literal: true

require "rails/generators"
require "rails/generators/named_base"

module Strata
  module Generators
    # Rails model generator that supports Strata attributes like :name, :address, :money, etc.
    # Automatically includes Strata::Attributes and creates appropriate database migrations
    class ModelGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :attributes, type: :array, default: [], banner: "field[:type][:index] field[:type][:index]"

      class_option :parent, type: :string, desc: "The parent class for the generated model"

      # Parse attributes manually to allow Strata types
      def initialize(args, *options)
        super
        parse_attributes!
      end

      def create_migration_file
        # Use strata:migration for all attributes since it supports both Strata and Rails types
        all_attrs = @parsed_attributes.map { |attr| "#{attr[:name]}:#{attr[:type]}" }

        if all_attrs.any?
          migration_name = "Create#{table_name.camelize}"
          generate("strata:migration", migration_name, *all_attrs)
        end
      end

      def create_model_file
        full_file_path = File.join(destination_root, "app/models", *Array(class_path), "#{file_name}.rb")
        if File.exist?(full_file_path)
          raise Thor::Error, "Model file already exists at app/models/#{Array(class_path).join('/')}/#{file_name}.rb"
        end

        template "model.rb.tt", File.join("app/models", class_path, "#{file_name}.rb")
      end

      private

      def parse_attributes!
        @parsed_attributes = attributes.map do |attribute|
          name, type = attribute.split(":")
          type ||= "string"
          { name: name, type: type.to_sym }
        end
      end

      def user_facing_id_key_for(attribute)
        # Feistel rejects key 0, so draw from [1, 2^32 - 1].
        attribute[:key] ||= SecureRandom.random_number(0xFFFF_FFFF) + 1
        "0x%08x" % attribute[:key]
      end

      def strata_attribute_type?(type)
        [ :name, :address, :money, :memorable_date, :us_date, :tax_id, :year_quarter, :user_facing_id ].include?(type.to_sym)
      end

      def has_strata_attributes?
        strata_attributes.any?
      end

      def strata_attributes
        @parsed_attributes.select { |attr| strata_attribute_type?(attr[:type]) }
      end

      def rails_attributes
        @parsed_attributes.reject { |attr| strata_attribute_type?(attr[:type]) }
      end

      def has_rails_attributes?
        rails_attributes.any?
      end

      def parent_class_name
        options[:parent] || "ApplicationRecord"
      end
    end
  end
end
