# frozen_string_literal: true

# Lookbook preview for the TaskListComponent.
class PaidLeaveTaskListPreview < Lookbook::Preview
  def default
    flow = PaidLeaveFlow.new(FactoryBot.build_stubbed(
      :paid_leave_application,
      name: "Name",
      leave_type: "medical"
    ))
    render Strata::Flows::TaskListComponent.new(
      flow:
    )
  end

  def with_step_label
    flow = PaidLeaveFlow.new(FactoryBot.build_stubbed(
      :paid_leave_application,
      name: "Name",
      leave_type: "medical"
    ))
    render Strata::Flows::TaskListComponent.new(
      flow:,
      show_step_label: true
    )
  end

  def diagram
    render template: "strata/previews/_business_process", locals: { business_process: PaidLeaveFlow }
  end
end
