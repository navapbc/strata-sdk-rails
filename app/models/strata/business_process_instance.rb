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

    # Starts the business process at its start step and executes that step.
    #
    # @param event [Hash] The event that started the process
    # @return [Symbol] :transitioned
    # @raise [StandardError] Whatever the start step raised, after logging it
    def start_from_event(event)
      Rails.logger.debug "Starting business process from event: #{event[:name]} with payload: #{event[:payload]}"
      apply_step(business_process.start_step_name)
      :transitioned
    end

    # Applies the transition this event defines for the current step, if any.
    #
    # The return value is what lets a caller tell applied work from a no-op.
    # Without it, an event arriving for a case already past that step is
    # indistinguishable from a transition that ran, so nothing can report or
    # count it.
    #
    # @param event [Hash] The event to apply
    # @return [Symbol] :transitioned if a transition applied, :no_match if none did
    # @raise [StandardError] Whatever the step raised, after logging it
    def transition_to_next_step(event)
      next_step = get_next_step(event[:name])
      return :no_match unless next_step

      Rails.logger.debug "Transitioning to step #{next_step} and executing the step"
      apply_step(next_step)
      :transitioned
    end

    private

    # Moves the case to a step and runs it, in one transaction.
    #
    # Committing the step change before the step runs is what makes a crash
    # unrecoverable: the case has advanced but the work never happened, and a
    # retry computes its next step from the already-advanced step, matches
    # nothing, and silently no-ops. Rolling both back together leaves the
    # event replayable.
    #
    # `requires_new: true` is load-bearing, not defensive. Events are published
    # from after_create/after_update and subscribers run inline, so in the path
    # that matters this runs inside the caller's open transaction — and a
    # nested `transaction` without it joins the outer one rather than opening a
    # savepoint, so the rollback would undo nothing at all. The bug would then
    # reproduce only in production, since a spec calling this directly gets a
    # real transaction and appears to pass.
    def apply_step(step_name)
      self.case.class.transaction(requires_new: true) do
        self.current_step = step_name
        self.case.save!
        execute_current_step
      end
    end

    def execute_current_step
      Rails.logger.debug "Executing current step: #{current_step} for case ID: #{self.case.id}"
      if current_step == "end"
        self.case.close
      else
        business_process.steps[current_step].execute(self.case)
      end
    rescue StandardError => e
      # Log and re-raise. Swallowing here is what would let a durable pipeline
      # record every failure as a success, and rescuing Exception absorbed
      # Interrupt and SignalException with it — so a step resisted Ctrl-C and
      # swallowed the deploy-time termination signal.
      Rails.logger.error "Error executing step #{current_step} for case ID: #{self.case.id} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end

    def get_next_step(event_name)
      business_process.transitions&.dig(current_step, event_name)
    end
  end
end
