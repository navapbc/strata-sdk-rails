# frozen_string_literal: true

module Strata
  module Cases
    # CaseRowComponent renders a single row in a cases table.
    # It displays case information including ID, creation date, and action links.
    #
    # This component is used by IndexComponent to render individual case rows.
    #
    # ## Customizing Step Descriptions
    #
    # Step descriptions can be customized by setting locale keys. The component
    # follows a specific hierarchy for determining step display text:
    #
    # 1. **Specific step locale key**: First checks for a specific locale key
    #    in the format: `{case_class_plural}.case_row_component.steps.{step_name}`
    #    Example: `passport_cases.case_row_component.steps.submit_application`
    #
    # 2. **Generic task type fallback**: If the specific step key is not found,
    #    use a generic description based on task type, such as:
    #    "Applicant: {humanized step name}", "Staff: {humanized step name}",
    #    "System: {humanized step name}", or "Third Party: {humanized step name}".
    #
    # ### Example Locale Configuration
    #
    # ```yaml
    # # config/locales/passport_cases/en.yml
    # en:
    #   passport_cases:
    #     case_row_component:
    #       steps:
    #         submit_application: "Submit Application"
    #         review_documents: "Review Documents"
    #         schedule_interview: "Schedule Interview"
    #       applicant_task: "Applicant: %{step_name}"
    #       staff_task: "Staff: %{step_name}"
    #       system_process: "System: %{step_name}"
    #       third_party_task: "Third Party: %{step_name}"
    # ```
    #
    # @example Basic usage
    #   <%= render CaseRowComponent.new(kase: @case) %>
    #
    class CaseRowComponent < ViewComponent::Base
      def initialize(kase:)
        @case = kase
      end

      def self.columns
        [
          :case_no,
          :assigned_to,
          :step,
          :due_on,
          :created_at
        ]
      end

      def self.headers
        columns.map { |column| t(".#{column}") }
      end

      protected

      def case_no
        link_to @case.id, polymorphic_path(@case)
      end

      def assigned_to
      end

      def step
        step_name = @case.business_process_instance.current_step
        step = @case.class.business_process.get_step(step_name)

        # Return the translated step name if available
        step_key = "#{@case.class.name.underscore.pluralize}.case_row_component.steps.#{step_name}"
        if I18n.exists?(step_key)
          return t(step_key)
        end

        # Fallback to logic based on the step class
        # Step type is one of: applicant_task, staff_task, system_process, third_party_task
        step_type = step.class.name.demodulize.underscore
        t(".#{step_type}", step_name: step_name.humanize)
      end

      def due_on
        pending_tasks_with_due_date = @case.tasks.select { |task| task.pending? && task.due_on.present? }
        pending_tasks_with_due_date.map(&:due_on).min&.strftime("%m/%d/%Y")
      end

      def created_at
        @case.created_at&.strftime("%m/%d/%Y")
      end
    end
  end
end
