# frozen_string_literal: true

require "rails/generators"
require "rails/generators/named_base"

# Rails generator for creating migrations with Strata attribute columns
module Strata
  module Generators
    # Generator that creates migrations for Strata attributes by mapping
    # each strata attribute type to its required database columns
    class MigrationGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("USAGE", __dir__)
      argument :attrs, type: :array, default: [], banner: "attribute:type attribute:type attribute:type:array attribute:type:range"

      def create_migration_file
        columns = []
        user_facing_id_sequence_columns = []
        attrs.each do |attribute_string|
          attribute_parts = attribute_string.split(":")
          name = attribute_parts.first
          type = attribute_parts[1]&.to_sym
          option = attribute_parts.last.to_sym

          columns += get_columns_for_attribute(name, type, option)
          user_facing_id_sequence_columns << "#{name}_sequence" if type == :user_facing_id
        end

        generate("migration", name, *columns)

        rewrite_bigint_to_bigserial!(user_facing_id_sequence_columns) if user_facing_id_sequence_columns.any?
      end

      private

      # Rails' migration generator rejects :bigserial (not in PostgreSQL's
      # native_database_types map), so we emit :bigint! and rewrite the
      # generated file to restore the autoincrementing sequence semantics.
      def rewrite_bigint_to_bigserial!(sequence_columns)
        migration_path = Dir.glob(File.join(destination_root, "db/migrate/*_#{name.underscore}.rb")).max
        return unless migration_path

        sequence_columns.each do |seq_col|
          gsub_file migration_path, /t\.bigint(\s+):#{Regexp.escape(seq_col)}\b/, "t.bigserial\\1:#{seq_col}", verbose: false
          gsub_file migration_path, /:#{Regexp.escape(seq_col)},(\s+):bigint\b/, ":#{seq_col},\\1:bigserial", verbose: false
        end
      end

      def get_columns_for_attribute(name, type, option = nil)
        if type == :user_facing_id
          if option == :array || option == :range
            raise ArgumentError, "user_facing_id attribute does not support :#{option} modifier"
          end
          return [ "#{name}_sequence:bigint!:uniq" ]
        end

        return [ "#{name}:jsonb" ] if option == :array

        if option == :range
          return get_columns_for_attribute("#{name}_start", type) +
                 get_columns_for_attribute("#{name}_end", type)
        end

        case type
        when :address
          [
            "#{name}_street_line_1:string",
            "#{name}_street_line_2:string",
            "#{name}_city:string",
            "#{name}_state:string",
            "#{name}_zip_code:string"
          ]
        when :array
          [ "#{name}:jsonb" ]
        when :memorable_date
          [ "#{name}:date" ]
        when :money
          [ "#{name}:integer" ]
        when :name
          [
            "#{name}_first:string",
            "#{name}_middle:string",
            "#{name}_last:string",
            "#{name}_suffix:string"
          ]
        when :tax_id
          [ "#{name}:string" ]
        when :us_date
          [ "#{name}:date" ]
        when :year_month
          [ "#{name}:string" ]
        when :year_quarter
          [ "#{name}:string" ]
        else
          # Allow built-in types like string, integer, etc.
          [ "#{name}:#{type}" ]
        end
      end
    end
  end
end
