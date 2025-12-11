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

    class_methods do
      def flow(flow_class)
        before_action :set_flow
        before_action :set_flow_task, only: flow_class.generated_routes

        # Set a @flow instance that can be evaluated against the current form record.
        # This is primarily useful in rendering progress within a task list or step indicator.
        define_method(:set_flow) do
          @flow = flow_class.new(flow_record)
        end

        # Set a @flow_task instance that can provide completion methods and routing helpers.
        define_method(:set_flow_task) do
          flow_class.tasks.each do |task|
            task.pages.each_with_index do |page, page_idx|
              # Search for the current page based on the request action
              if [ page.edit_pathname.to_sym, page.update_pathname.to_sym ].include?(request.path_parameters[:action].to_sym)
                @flow_page = page
                @flow_task = Flows::TaskEvaluator.new(task, flow_record, page_idx)
                return
              end
            end
          end
        end

        # For each question page, define the edit and update paths.
        flow_class.pages.each_with_index do |page, page_idx|
          # /{record_class}/:id/edit_{question_page_name}
          define_method(page.edit_pathname) do
          end

          # /{record_class}/:id/update_{question_page_name}
          define_method(page.update_pathname) do
            # Permit attributes based on the fields defined on the question page
            record_class_name = flow_record.class.name.underscore.to_sym
            form_params = params.require(record_class_name).permit(*(page.fields))
            flow_record.assign_attributes(form_params)

            if flow_record.valid? && flow_record.save(context: page.name)
              redirect_to @flow_task.next_path || @flow.start_path
            else
              # Allow custom error-handling behaviors by defining :on_flow_update_invalid
              if respond_to?(:on_flow_update_invalid)
                on_flow_update_invalid
              else
                flash.now[:errors] = flow_record.errors.full_messages
              end

              render page.edit_pathname, status: :unprocessable_entity
            end
          end
        end
      end
    end
  end
end
