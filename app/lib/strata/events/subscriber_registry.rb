# frozen_string_literal: true

module Strata
  module Events
    # SubscriberRegistry records the durable subscribers of each event under a stable
    # subscriber key, such as "PassportBusinessProcess.handle_event", so a delivery can
    # name its subscriber and a worker can find the registered callback again.
    #
    # Only methods on named classes or modules can be registered. A subscriber key is
    # only ever looked up among registered subscribers, never loaded by name, so a
    # tampered delivery row cannot make a worker call arbitrary code.
    #
    # See docs/specs/durable-events/spec.md#subscriber-types.
    class SubscriberRegistry
      # Returns the subscriber key for a method on a named class or module whose name
      # still refers to it, or nil for any other callback.
      #
      # @param [Object] callback
      # @return [String, nil] a key such as "MyBusinessProcess.handle_event"
      def self.subscriber_key(callback)
        return unless callback.is_a?(Method)

        receiver = callback.receiver
        return unless receiver.is_a?(Module) && receiver.name
        return unless Object.const_defined?(receiver.name) && Object.const_get(receiver.name).equal?(receiver)

        "#{receiver.name}.#{callback.name}"
      end

      def initialize
        @callbacks = {}
        @subscriptions = {}
      end

      # Registers a callback as a durable subscriber of an event. The block subscribes
      # the callback and returns the subscription; it runs only if the callback can be
      # registered, so a rejected callback is never subscribed.
      #
      # @param [String] event_key
      # @param [Object] callback
      # @yieldreturn [Object] the subscription
      # @return [Object] the subscription
      # @raise [NonDurableSubscriberError] if the callback is not a method on a named class or module
      # @raise [DuplicateSubscriberError] if the callback already subscribes to the event
      def register(event_key, callback)
        key = registrable_key(event_key, callback)
        subscription = yield

        (@callbacks[event_key] ||= {})[key] = callback
        @subscriptions[subscription] = [ event_key, key ]
        subscription
      end

      # Removes the durable subscriber a subscription registered, if any.
      #
      # @param [Object] subscription
      def remove(subscription)
        event_key, key = @subscriptions.delete(subscription)
        return unless key

        @callbacks[event_key].delete(key)
        @callbacks.delete(event_key) if @callbacks[event_key].empty?
      end

      # Removes every durable subscriber.
      def clear
        @callbacks.clear
        @subscriptions.clear
      end

      # @param [String] event_key
      # @return [Array<String>] the event's subscriber keys, in subscription order
      def keys(event_key)
        @callbacks.fetch(event_key, {}).keys
      end

      # @param [String] event_key
      # @param [String] subscriber_key
      # @return [Method] the callback registered for the event under the key
      # @raise [UnknownSubscriberError] if no such subscriber is registered for the event
      def fetch(event_key, subscriber_key)
        @callbacks.fetch(event_key, {}).fetch(subscriber_key) do
          raise UnknownSubscriberError, "No durable subscriber #{subscriber_key} is registered for event '#{event_key}'"
        end
      end

      private

      def registrable_key(event_key, callback)
        key = self.class.subscriber_key(callback)
        unless key
          raise NonDurableSubscriberError,
            "Cannot subscribe #{callback.class.name} to event '#{event_key}' while Strata::Events.durable is enabled. " \
            "A durable subscriber must be a named class or module method, such as MyHandler.method(:handle_event), " \
            "so a worker can find it by name. Lambdas, procs, and other callables are supported only while durability is disabled."
        end

        if @callbacks.fetch(event_key, {}).key?(key)
          raise DuplicateSubscriberError,
            "#{key} is already subscribed to event '#{event_key}'; a durable subscriber can subscribe to an event only once"
        end

        key
      end
    end
  end
end
