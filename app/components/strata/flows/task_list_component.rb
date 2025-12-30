# frozen_string_literal: true

module Strata
  module Flows
    # TaskListComponent renders a collection of tasks as an unordered list.
    #
    # ## Step Descriptions
    #
    # Step descriptions in the table can be customized through locale keys.
    # See CaseRowComponent documentation for more information.
    #
    # @example Basic usage
    #   <%= render IndexComponent.new(cases: @cases, model_class: MyCase) %>
    #
    class TaskListComponent < ViewComponent::Base
      def initialize(
        flow:,
        task_section_component_class: TaskSectionComponent,
        show_step_label: false
      )
        @flow = flow
        @task_section_component_class = task_section_component_class
        @show_step_label = show_step_label
      end
    end
  end
end
