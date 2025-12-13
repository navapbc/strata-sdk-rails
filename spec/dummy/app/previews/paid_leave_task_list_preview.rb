# frozen_string_literal: true

# Lookbook preview for the TaskListComponent.
class PaidLeaveTaskListPreview < ViewComponent::Preview
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
end
