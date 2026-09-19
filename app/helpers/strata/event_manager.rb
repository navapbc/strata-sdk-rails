# frozen_string_literal: true

module Strata
  # EventManager is a pub/sub system for workflow events.
  # It allows components to communicate with each other asynchronously
  # through event publishing and subscription.
  #
  # This class is used throughout the Strata SDK for handling transitions
  # between workflow steps and notifying components of state changes.
  #
  # @example Publishing an event
  #   Strata::EventManager.publish("FormSubmitted", { form_id: 123 })
  #
  # @example Subscribing to an event
  #   subscription = Strata::EventManager.subscribe("FormSubmitted") do |event|
  #     # Handle the event
  #     puts "Form #{event[:payload][:form_id]} was submitted"
  #   end
  #
  class EventManager
    @@subscriptions = []

    class << self
      # Subscribes to an event, registering a callback to be executed when the event occurs.
      #
      # @param [String] event_key The name of the event to subscribe to
      # @param [Proc, Method] callback The callback to execute when the event occurs
      # @return [Object] The subscription object, which can be used to unsubscribe
      def subscribe(event_key, callback)
        subscription = ActiveSupport::Notifications.subscribe(event_key) do |name, _started, _finished, _unique_id, payload|
          callback.call({
            name: name,
            payload: payload
          })
        end

        @@subscriptions << subscription
        subscription
      end

      # Unsubscribes from an event by providing the subscription object.
      #
      # @param [Object] subscription The subscription object returned by subscribe
      def unsubscribe(subscription)
        ActiveSupport::Notifications.unsubscribe(subscription)
      end

      # Unsubscribes from all events that have been registered.
      # Used when Zeitwerk is unloading EventManager during class reloading.
      #
      # @return [void]
      def unsubscribe_all
        @@subscriptions.each do |subscription|
          ActiveSupport::Notifications.unsubscribe(subscription)
        end
        @@subscriptions.clear
      end

      # Publishes an event with the given key and payload.
      #
      # Subscriber errors are logged and swallowed. They are deliberately not
      # propagated: publish is called from after_create/after_update rather
      # than after_commit, and instrument runs subscribers inline on the same
      # thread, so an error escaping here aborts the caller's save!. For
      # ApplicationForm#publish_created that means rejecting a submitted
      # form — worse than the stuck case it would replace, and with no retry
      # machinery yet to recover from it.
      #
      # This rescue is temporary. Once handlers run in a background job there
      # is no domain write to unwind and a raise is precisely what drives the
      # retry, so it comes out then. Signals and other non-StandardError
      # exceptions are left alone, so a deploy-time termination still
      # terminates.
      #
      # @param [String] event_key The name of the event to publish
      # @param [Hash] payload The event payload data
      # @return [void]
      def publish(event_key, payload = {})
        Rails.logger.debug "Event Manager: Publishing event '#{event_key}' with payload: #{payload.inspect}"
        ActiveSupport::Notifications.instrument(event_key, payload)
        nil
      rescue StandardError => e
        Rails.logger.error "Event Manager: subscriber error while publishing '#{event_key}' - #{e.message}"
        Rails.logger.error e.backtrace&.join("\n")
        nil
      end
    end

    private

    def initialize
      # setting initialize to private so that we cannot make new instances of it
    end
  end
end
