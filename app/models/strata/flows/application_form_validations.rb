# frozen_string_literal: true

module Strata::Flows
  # Provides utilities for performing model validations against ApplicationFormFlow contexts.
  module ApplicationFormValidations
    extend ActiveSupport::Concern

    class_methods do
      # A container module for constants.
      module Flow
      end

      # Defines validation context constants for each question page in the provided flow, which are used
      # for determining the page's completion state.
      #
      # All contexts within the flow will also be auto-validated upon submit.
      #
      # @example
      #   validate_flow LeaveApplicationFlow
      #   validates :applicant_name_first, presence: true, on: Flow::NAME
      #   validates :applicant_name_last, presence: true, on: Flow::NAME
      #
      def validate_flow(flow_class, validate_on_submit: true)
        flow_class.contexts.each do |context|
          Flow.const_set(context.upcase.to_sym, context)
        end

        if validate_on_submit
          validate -> { valid?(flow_class.contexts) }, on: :submit
        end
      end
    end
  end
end
