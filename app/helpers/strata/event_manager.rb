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
    @@durable_subscribers = Strata::Events::SubscriberRegistry.new

    class << self
      # Subscribes to an event, registering a callback to be executed when the event occurs.
      #
      # When {Strata::Events.durable} is enabled, the callback must be a method on a named
      # class or module, such as +MyBusinessProcess.method(:handle_event)+, and is registered
      # as a durable subscriber under a key such as "MyBusinessProcess.handle_event".
      #
      # @param [String] event_key The name of the event to subscribe to
      # @param [Proc, Method] callback The callback to execute when the event occurs
      # @return [Object] The subscription object, which can be used to unsubscribe
      # @raise [Strata::Events::NonDurableSubscriberError] if durable and the callback is not a named method
      # @raise [Strata::Events::DuplicateSubscriberError] if durable and the callback already subscribes to the event
      def subscribe(event_key, callback)
        subscription =
          if Strata::Events.durable
            @@durable_subscribers.register(event_key, callback) { listen(event_key, callback) }
          else
            listen(event_key, callback)
          end

        @@subscriptions << subscription
        Strata::Events.active_subscriptions = @@subscriptions.size
        subscription
      end

      # Unsubscribes from an event by providing the subscription object.
      # Unsubscribing a subscription that was already removed does nothing.
      #
      # @param [Object] subscription The subscription object returned by subscribe
      def unsubscribe(subscription)
        ActiveSupport::Notifications.unsubscribe(subscription)
        return unless @@subscriptions.delete(subscription)

        @@durable_subscribers.remove(subscription)
        Strata::Events.active_subscriptions = @@subscriptions.size
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
        @@durable_subscribers.clear
        Strata::Events.active_subscriptions = 0
      end

      # Returns the keys of the durable subscribers of an event, in subscription order.
      #
      # @param [String] event_key The name of the event
      # @return [Array<String>] subscriber keys, such as "MyBusinessProcess.handle_event"
      def subscriber_keys(event_key)
        @@durable_subscribers.keys(event_key)
      end

      # Returns the callback registered for a durable subscriber of an event. Only registered
      # subscribers are returned; a subscriber key is never resolved by loading it by name.
      #
      # @param [String] event_key The name of the event
      # @param [String] subscriber_key The subscriber key, such as "MyBusinessProcess.handle_event"
      # @return [Method] the registered callback
      # @raise [Strata::Events::UnknownSubscriberError] if the subscriber is not registered for the event
      def subscriber(event_key, subscriber_key)
        @@durable_subscribers.fetch(event_key, subscriber_key)
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
        Rails.logger.error "Event Manager: Subscriber #{subscriber} failed handling event '#{event[:name]}' - " \
          "#{e.full_message(highlight: false)}"
        Rails.error.report(e, handled: true, severity: :error, context: { event: event[:name], subscriber: subscriber })
      end

      def listen(event_key, callback)
        ActiveSupport::Notifications.subscribe(event_key) do |name, _started, _finished, _unique_id, payload|
          call_subscriber(callback, { name: name, payload: payload })
        end
      end

      def subscriber_name(callback)
        Strata::Events::SubscriberRegistry.subscriber_key(callback) || callback.class.name
      end
    end

    private

    def initialize
      # setting initialize to private so that we cannot make new instances of it
    end
  end
end
