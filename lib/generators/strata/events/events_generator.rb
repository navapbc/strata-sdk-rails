# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Strata
  module Generators
    # Generator that installs the strata_events and strata_event_deliveries
    # migration into the host application. The Strata::Event and
    # Strata::EventDelivery models are shipped by the engine directly — only
    # the migration needs to be copied because Rails engines don't auto-load
    # engine migrations.
    #
    # @example Install the durable events migration
    #   rails generate strata:events
    class EventsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      class_option :"skip-migration-check", type: :boolean, default: false,
                                            desc: "Skip checking if strata_events table exists"

      def create_migration_file
        migration_template "create_strata_events.rb.tt", File.join(db_migrate_path, "create_strata_events.rb")
      end

      def check_strata_events_table
        return if options[:"skip-migration-check"]
        return if ActiveRecord::Base.connection.table_exists?(:strata_events)

        say "Warning: strata_events table does not exist.", :yellow
        if yes?("Would you like to run 'bin/rails db:migrate' now? (y/n)")
          rails_command "db:migrate"
        else
          say "You may need to run 'bin/rails db:migrate' before using durable events.", :yellow
        end
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
        # The migration is already written; db:migrate can't run until the database exists.
        say "Warning: could not connect to the database. " \
            "Run 'bin/rails db:create db:migrate' before using durable events.", :yellow
      end
    end
  end
end
