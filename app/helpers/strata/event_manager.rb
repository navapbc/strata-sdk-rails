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
          call_subscriber(callback, { name: name, payload: payload })
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
      # @param [String] event_key The name of the event to publish
      # @param [Hash] payload The event payload data
      # @return [void]
      def publish(event_key, payload = {})
        publish_reporting_failures(event_key, payload)
        nil
      end

      # Publishes an event like {publish} and returns the subscribers that failed.
      # Used by the strata:events rake tasks so an operator republishing an event can
      # tell whether it worked. Temporary until durable delivery records failures
      # (see docs/specs/durable-events/spec.md).
      #
      # @param [String] event_key The name of the event to publish
      # @param [Hash] payload The event payload data
      # @return [Array<Hash>] One { subscriber:, error: } entry per subscriber that raised
      #   while handling this event. Failures from events those subscribers publish are
      #   not included.
      def publish_reporting_failures(event_key, payload = {})
        Rails.logger.debug "Event Manager: Publishing event '#{event_key}' with payload: #{payload.inspect}"
        failures = []
        outer_failures = current_failures
        self.current_failures = failures
        ActiveSupport::Notifications.instrument(event_key, payload)
        failures
      ensure
        self.current_failures = outer_failures
      end

      private

      # Runs the subscriber in a savepoint so its failure rolls back only its own changes,
      # not the publisher's write or other subscribers'. This is a temporary publish-boundary
      # rescue until durable delivery jobs handle failures (see docs/specs/durable-events/spec.md).
      def call_subscriber(callback, event)
        ActiveRecord::Base.transaction(requires_new: true) do
          callback.call(event)
        end
      rescue StandardError => e
        subscriber = subscriber_name(callback)
        current_failures&.push({ subscriber: subscriber, error: e })
        Rails.logger.error "Event Manager: Subscriber #{subscriber} failed handling event '#{event[:name]}' - " \
          "#{e.full_message(highlight: false)}"
        Rails.error.report(e, handled: true, severity: :error, context: { event: event[:name], subscriber: subscriber })
      end

      # Failures collected for the innermost publish on this thread or fiber.
      def current_failures
        ActiveSupport::IsolatedExecutionState[:strata_event_manager_failures]
      end

      def current_failures=(failures)
        ActiveSupport::IsolatedExecutionState[:strata_event_manager_failures] = failures
      end

      def subscriber_name(callback)
        return "#{callback.receiver.name}.#{callback.name}" if callback.is_a?(Method) && callback.receiver.is_a?(Module)

        callback.class.name
      end
    end

    private

    def initialize
      # setting initialize to private so that we cannot make new instances of it
    end
  end
end
