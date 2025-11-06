# frozen_string_literal: true

require "rails/generators"

module Strata
  module Generators
    # Generator for creating Strata::Task subclasses with standardized templates.
    # Supports custom parent classes and database migration checking.
    class TaskGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :parent, type: :string, desc: "The parent class for the generated task"
      class_option :"skip-migration-check", type: :boolean, default: false, desc: "Skip checking if strata_tasks table exists"

      def initialize(*args, &block)
        super
        @task_name = format_task_name(name)
        @parent_class = options[:parent] || "Strata::Task"
      end

      def create_task_file
        check_strata_tasks_table
        template "task.rb", File.join("app/models", "#{file_path}.rb")
      end

      def create_test_file
        template "task_spec.rb", File.join("spec/models", "#{file_path}_spec.rb")
      end

      private

      def check_strata_tasks_table
        return if options[:"skip-migration-check"]

        unless ActiveRecord::Base.connection.table_exists?(:strata_tasks)
          say "Warning: strata_tasks table does not exist.", :yellow
          if yes?("Would you like to create and run the strata_tasks migration now? (y/n)")
            create_strata_tasks_migration
            rails_command "db:migrate"
          else
            say "You may need to create the strata_tasks migration and run 'bin/rails db:migrate' before using your task class.", :yellow
          end
        end
      end

      def create_strata_tasks_migration
        # Check if migration already exists
        migration_name = "create_strata_tasks"
        migration_files = Dir.glob(File.join(destination_root, "db/migrate/*_#{migration_name}.rb"))

        if migration_files.any?
          say "Migration for strata_tasks already exists, skipping creation.", :yellow
          return
        end

        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        template "create_strata_tasks.rb.tt", "db/migrate/#{timestamp}_#{migration_name}.rb"
      end

      def format_task_name(name)
        formatted = name.underscore.classify
        formatted.end_with?("Task") ? formatted : "#{formatted}Task"
      end

      def file_path
        @task_name.underscore
      end
    end
  end
end
