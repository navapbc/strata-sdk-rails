# frozen_string_literal: true

require "rails/generators"

module Strata
  module Generators
    # Generator that creates a Determination model, concern, migration, and spec for the host application.
    # The generated files inherit from Strata::Determination and Strata::Determinable to provide
    # determination recording capabilities with customization hooks.
    #
    # @example Generate determination scaffold
    #   rails generate strata:determination
    #
    class DeterminationGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :"skip-migration-check", type: :boolean, default: false, desc: "Skip checking if strata_determinations table exists"

      def create_migration_file
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        template "create_strata_determinations.rb.tt", "db/migrate/#{timestamp}_create_strata_determinations.rb"
      end

      def create_determination_model
        template "determination.rb.tt", "app/models/determination.rb"
      end

      def create_determinable_concern
        template "determinable.rb.tt", "app/models/concerns/determinable.rb"
      end

      def create_determination_spec
        template "determination_spec.rb.tt", "spec/models/determination_spec.rb"
      end

      def create_determinable_spec
        template "determinable_spec.rb.tt", "spec/models/concerns/determinable_spec.rb"
      end

      def check_strata_determinations_table
        return if options[:"skip-migration-check"]

        unless ActiveRecord::Base.connection.table_exists?(:strata_determinations)
          say "Warning: strata_determinations table does not exist.", :yellow
          if yes?("Would you like to run 'bin/rails db:migrate' now? (y/n)")
            rails_command "db:migrate"
          else
            say "You may need to run 'bin/rails db:migrate' before using your determination class.", :yellow
          end
        end
      end
    end
  end
end
