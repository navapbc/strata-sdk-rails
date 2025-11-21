# frozen_string_literal: true

require "rails/generators"

module Strata
  module Generators
    # Generator for creating staff dashboard components for applications using the `strata` gem
    class StaffGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates staff dashboard components for applications using the `strata` gem"

      def create_staff_controller
        template "staff_controller.rb", "app/controllers/staff_controller.rb"
      end

      def create_tasks_controller
        template "tasks_controller.rb", "app/controllers/tasks_controller.rb"
      end

      def create_views
        template "staff_index.html.erb", "app/views/staff/index.html.erb"
        template "tasks_index.html.erb", "app/views/tasks/index.html.erb"
        template "task_show.html.erb", "app/views/tasks/show.html.erb"
      end

      def create_spec
        template "tasks_spec.rb", "spec/requests/tasks_spec.rb"
      end

      def update_routes
        route <<~ROUTES
          scope path: "/staff" do
            # Add staff specific resources here, like cases and tasks

            resources :tasks, only: [ :index, :show, :update ] do
              collection do
                post :pick_up_next_task
              end
            end
          end

          get "staff", to: "staff#index"
        ROUTES
      end

      def print_next_steps
        say "\n" + set_color("Next Steps:", :green, :bold)
        say "  1. Customize the case_classes method in app/controllers/staff_controller.rb"
        say "     Example: def case_classes; [MyCase, AnotherCase]; end"
        say "  2. Implement authentication and authorization policies in StaffController"
        say "  3. Ensure your Task model has: belongs_to :case, class_name: \"YourCaseClass\""
        say "  4. Ensure your Case model has: has_one :application_form, ..."
        say "  5. Implement the pending tests in spec/requests/tasks_spec.rb"
        say "  6. Customize the staff dashboard view in app/views/staff/index.html.erb"
        say "\n" + set_color("Generated routes available at:", :blue, :bold)
        say "  GET    /staff                    (staff dashboard)"
        say "  GET    /staff/tasks              (tasks index)"
        say "  GET    /staff/tasks/:id          (task show)"
        say "  PATCH  /staff/tasks/:id          (task update)"
        say "  POST   /staff/tasks/pick_up_next_task (assign next task)"
      end
    end
  end
end
