# frozen_string_literal: true

module Strata
  module Flows
    # Extends ActionDispatch::Routing::Mapper with a `mount_flow_routes` helper
    # that generates all routes implied by an ApplicationFormFlow definition:
    # member actions for top-level pages, and nested resources with member
    # actions for loop pages.
    #
    # @example
    #   resources :leave_applications, only: [ :index, :new, :show, :create ] do
    #     member do
    #       get :review
    #       patch :submit
    #     end
    #
    #     mount_flow_routes Flows::LeaveApplicationFlow
    #   end
    module RoutingExtensions
      # Mounts edit/update routes for every QuestionPage in the flow.
      #
      # Must be called inside a `resources` block. The enclosing resource's
      # controller is used for all generated actions unless `controller:` is
      # explicitly provided.
      def mount_flow_routes(flow_class, controller: nil)
        target_controller = controller || parent_resource&.controller
        raise ArgumentError, "mount_flow_routes must be called inside a resources block, or given an explicit controller:" unless target_controller

        member do
          flow_class.all_pages.reject(&:in_loop?).each do |page|
            get page.edit_pathname
            patch page.update_pathname
          end
        end

        loop_nodes = flow_class.tasks.flat_map(&:pages).select { |item| item.is_a?(Strata::Flows::Loop) }
        loop_nodes.each do |loop_node|
          resources loop_node.association, only: [], controller: target_controller do
            member do
              loop_node.pages.each do |page|
                get page.edit_pathname
                patch page.update_pathname
              end
            end
          end
        end
      end
    end
  end
end
