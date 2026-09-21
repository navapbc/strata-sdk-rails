# frozen_string_literal: true

module Strata
  # BusinessProcess is a class that allows you to define and execute business workflows with steps and event-driven transitions.
  #
  # Business process definitions should be placed in app/business_processes/ with the naming convention
  # *_business_process.rb (e.g. passport_business_process.rb, approval_business_process.rb)
  #
  # @example Defining a passport business process in app/business_processes/passport_business_process.rb
  # class PassportBusinessProcess < Strata::BusinessProcess
  #   # Define steps
  #   applicant_task('submit_application')
  #
  #   system_process('verify_identity', ->(kase) {
  #     IdentityVerificationService.new(kase).verify_identity
  #   })
  #
  #   staff_task('review_application', PassportTask)
  #
  #   # Define start step
  #   start_on_application_form_created('submit_application')
  #
  #   # Define transitions
  #   transition('submit_application', 'PassportApplicationFormSubmitted', 'verify_identity')
  #   transition('verify_identity', 'IdentityVerified', 'review_application')
  #   transition('review_application', 'DecisionMade', 'end')
  # end
  #
  # See app/models/strata/business_process_builder.rb for more step options
  # and docs/case-management-business-process.md for more details.
  #
  # The process automatically listens for events and transitions between steps
  # based on the defined transitions. Events can be triggered by either user actions
  # or system processes. When a step transitions to 'end', the case is automatically closed.
  #
  # Event payloads must contain either case_id or application_form_id to identify the case.
  #
  # @see Strata::StaffTask
  # @see Strata::SystemProcess
  #
  # Key Methods:
  # - start_listening_for_events: Starts listening for events that trigger transitions
  # - stop_listening_for_events: Stops listening for events (useful for cleanup)
  #
  # Class Methods:
  # @method define(name, case_class)
  #   Creates a new BusinessProcess definition. Also automatically starts listening for events.
  #   @param [Symbol] name The name of the business process
  #   @param [Class] case_class The case class this process operates on
  #   @yield [BusinessProcessBuilder] builder DSL for defining the process steps and transitions
  #   @return [BusinessProcess] The configured and activated business process
  #
  # Instance Methods:
  # @method start_listening_for_events
  #   Starts listening for events that can trigger transitions. Called automatically by define.
  #
  # @method stop_listening_for_events
  #   Stops listening for events and cleans up subscriptions. Useful for cleanup in tests.
  #
  class BusinessProcess
    include BusinessProcessBuilder

    def self.case_class
      name.sub("BusinessProcess", "Case").constantize
    end

    def self.get_step(name)
      steps[name]
    end

    def self.to_mermaid
      diagram = "flowchart TD\n"

      steps.each do |name, step|
        node_name = name.gsub(" ", "_")
        node_class = step.class.name.demodulize
        diagram += "  #{node_name}:::#{node_class}\n"
      end

      diagram += "  END((End))\n"

      transitions.each do |from, events|
        events.each do |event, to|
          # Capitalize the "END" node since Mermaid breaks if one of the nodes is named "end" https://github.com/mermaid-js/mermaid/issues/1444
          to = "END" if to == "end"
          diagram += "  #{from} -->|#{event}| #{to}\n"
        end
      end

      diagram += [
        "classDef ApplicantTask fill:#90EE90,stroke:#333,stroke-width:2px;",
        "classDef StaffTask fill:#ffb366,stroke:#333,stroke-width:2px;",
        "classDef SystemProcess fill:#a0d8ef,stroke:#333,stroke-width:2px;",
        "classDef ThirdPartyTask fill:#c0c0ff,stroke:#333,stroke-width:2px;"
      ].join("\n")

      diagram
    end

    class << self
      def subscriptions
        @subscriptions ||= {}
      end

      def start_listening_for_events
        @listening ||= false
        if @listening
          Rails.logger.debug "Strata::BusinessProcess with name #{name} already listening for events"
          return
        end

        get_event_names.each do |event_name|
          Rails.logger.debug "Strata::BusinessProcess with name #{name} subscribing to event: #{event_name}"
          subscriptions[event_name] = Strata::EventManager.subscribe(event_name, method(:handle_event))
        end

        @listening = true
      end

      def stop_listening_for_events
        Rails.logger.debug "Strata::BusinessProcess with name #{name} stopping listening for events"

        subscriptions.each do |event_name, subscription|
          Rails.logger.debug "Strata::BusinessProcess with name #{name} unsubscribing from event: #{event_name}"
          Strata::EventManager.unsubscribe(subscription)
        end
        subscriptions.clear
        @listening = false
      end
    end

    private

    class << self
      def create_case_from_event(event)
        Rails.logger.debug "Creating case from event: #{event[:name]} with payload: #{event[:payload]}"
        handler = start_events[event[:name]]
        raise RuntimeError, "No handler defined for start event '#{event[:name]}'" unless handler

        kase = handler.call(event)
        kase.save!
        kase
      end

      def get_event_names
        transitions.values.flat_map(&:keys).uniq | start_events.keys
      end

      def handle_event(event)
        Rails.logger.debug "Handling event: #{event[:name]} with payload: #{event[:payload]}"

        if start_event?(event[:name])
          kase = create_case_from_event(event)
          return kase.business_process_instance.start_from_event(event)
        else
          outcomes = case_class.for_event(event).map do |kase|
            kase.business_process_instance.transition_to_next_step(event)
          end

          return :transitioned if outcomes.include?(:transitioned)
        end

        :no_match
      end

      def from_event(event)
        kase = create_case_from_event(event)
        kase.business_process_instance
      end

      def start_event?(event_name)
        start_events.key?(event_name)
      end
    end
  end
end
