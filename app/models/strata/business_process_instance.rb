# frozen_string_literal: true

module Strata
  # BusinessProcessInstance represents the runtime state and behavior of a business process
  # for a specific case. It manages the current step in the process flow and handles transitions
  # between steps based on events.
  #
  # This class acts as a bridge between the business process definition (BusinessProcess)
  # and the case it operates on. It maintains the current state and executes steps as
  # the process moves forward.
  #
  # @example Transitioning to the next step based on an event
  #   instance = case.business_process_instance
  #   instance.transition_to_next_step({ name: 'form_submitted', payload: { case_id: case.id } })
  #
  # Key features:
  # - Manages the current step in the business process for a specific case
  # - Handles transitions between steps based on events
  # - Executes the current step's logic (staff tasks, system processes, etc.)
  # - Closes the case when reaching the end step
  #
  # @see Strata::BusinessProcess
  # @see Strata::Case
  #
  class BusinessProcessInstance
    attr_reader :case

    def initialize(kase, current_step)
      @case = kase
    end

    # BusinessProcessInstance is conceptually a value object associated with a Case.
    # Rather than having a separate table for business process instances, the data
    # (like current_step) is stored directly on the case table itself. This design
    # choice trades off logical separation for query performance by avoiding table joins.
    # An alternative implementation could store business process instance data in a
    # separate table, which would be logically cleaner but require joins during DB queries.
    def current_step
      self.case.business_process_current_step
    end

    # Sets the current step on the underlying case record.
    # See the comment above current_step for explanation of this implementation approach.
    def current_step=(step)
      self.case.business_process_current_step = step
    end

    def business_process
      self.case.class.business_process
    end

    def start_from_event(event)
      Rails.logger.debug "Starting business process from event: #{event[:name]} with payload: #{event[:payload]}"
      self.current_step = business_process.start_step_name
      self.case.save!
      execute_current_step
      :transitioned
    end

    def transition_to_next_step(event)
      next_step = get_next_step(event[:name])
      return :no_match unless next_step

      Rails.logger.debug "Transitioning to step #{next_step} and executing the step"
      self.current_step = next_step
      self.case.save!
      execute_current_step
      :transitioned
    end

    private

    def execute_current_step
      begin
        Rails.logger.debug "Executing current step: #{current_step} for case ID: #{self.case.id}"
        if current_step == "end"
          self.case.close
        else
          business_process.steps[current_step].execute(self.case)
        end
      rescue Exception => e
        Rails.logger.error "Error executing step #{current_step} for case ID: #{self.case.id} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    def get_next_step(event_name)
      business_process.transitions&.dig(current_step, event_name)
    end
  end
end
