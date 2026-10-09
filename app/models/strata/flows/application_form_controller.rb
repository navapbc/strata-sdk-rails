# frozen_string_literal: true

module Strata::Flows
  # Generalizes the page structure for a multi-page form based on an ApplicationFormFlow.
  #
  # @example
  #   class LeaveApplicationsController
  #     include Flows::ApplicationFormController
  #
  #     flow Flows::LeaveApplicationFlow
  #     layout "leave_application_form", only: Flows::LeaveApplicationFlow.generated_routes
  #
  #     ...
  #
  #     def flow_record
  #       @leave_application
  #     end
  #   end
  module ApplicationFormController
    extend ActiveSupport::Concern

    def flow_record
      raise NotImplementedError, "#{self.class.name} must define #flow_record"
    end

    # Resolves the flow record id from request params, handling both top-level
    # routes (where params[:id] is the flow record) and loop-nested routes
    # (where params[:id] is the loop child and params["<flow_class>_id"] is
    # the flow record).
    def flow_record_id
      parent_key = "#{controller_name.singularize}_id"
      params[parent_key] || params[:id]
    end

    class_methods do
      def flow(flow_class)
        before_action :set_flow
        before_action :set_flow_task, only: flow_class.generated_routes
        before_action :enforce_task_dependencies, only: flow_class.generated_routes

        # Set a @flow instance that can be evaluated against the current form record.
        # This is primarily useful in rendering progress within a task list or step indicator.
        define_method(:set_flow) do
          @flow = flow_class.new(flow_record)
        end

        # Set a @flow_task instance that can provide completion methods and routing helpers.
        define_method(:set_flow_task) do
          @flow_page, @flow_task = flow_class.find_page_and_task_by_action(
            flow_record,
            request.path_parameters[:action],
            request.path_parameters[:id]
          )
        end

        # Redirect to start_path if the current page's task has unmet dependencies.
        define_method(:enforce_task_dependencies) do
          return unless @flow_task

          unless @flow_task.task.dependencies_met?(@flow)
            redirect_to @flow.start_path
          end
        end

        # For each question page (including pages inside loops), define the edit
        # and update actions. Action names are namespaced by loop name for loop
        # pages (e.g. update_prior_employer_business_name).
        flow_class.all_pages.each do |page|
          # /{record_class}/:id/edit_{question_page_name} (or nested under loop child)
          define_method(page.edit_pathname) do
          end

          # /{record_class}/:id/update_{question_page_name} (or nested under loop child)
          define_method(page.update_pathname) do
            # For loop pages, reuse the loop_record already resolved by set_flow_task
            # so that assign_attributes/errors land on the same instance the view
            # renders, preserving submitted values across a re-render.
            target_record = page.in_loop? ? @flow_task.loop_record : flow_record

            record_class_name = target_record.class.name.underscore.to_sym
            form_params = params.require(record_class_name).permit(*(page.attributes(target_record.class)))
            target_record.assign_attributes(form_params)

            if target_record.valid? && target_record.save(context: page.name)
              redirect_to @flow_task.next_path || (@flow.tasks.length == 1 ? @flow.end_path : @flow.start_path)
            else
              # Allow custom error-handling behaviors by defining :on_flow_update_invalid
              if respond_to?(:on_flow_update_invalid)
                on_flow_update_invalid(target_record)
              else
                flash.now[:errors] = target_record.errors.full_messages
              end

              render page.edit_pathname, status: :unprocessable_content
            end
          end
        end
      end
    end
  end
end
