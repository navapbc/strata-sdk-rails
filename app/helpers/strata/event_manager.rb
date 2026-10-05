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
        Rails.logger.debug "Event Manager: Publishing event '#{event_key}' with payload: #{payload.inspect}"
        ActiveSupport::Notifications.instrument(event_key, payload)
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
        Rails.logger.error "Event Manager: Subscriber #{subscriber} failed handling event '#{event[:name]}' - #{e.class}: #{e.message}"
        Rails.error.report(e, handled: true, context: { event: event[:name], subscriber: subscriber })
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
