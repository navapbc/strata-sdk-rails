# frozen_string_literal: true

module Strata
  # Events holds the durable events configuration and errors.
  #
  # It lives outside the autoloaded paths so code reloading does not reset the
  # configuration while subscriptions made at boot remain registered.
  #
  # See docs/specs/durable-events/spec.md#configuration.
  module Events
    class Error < StandardError; end

    # Raised when the configuration is invalid or changed after subscriptions are registered.
    class ConfigurationError < Error; end

    # Raised when durability is enabled and a subscriber cannot be found by name in a worker.
    class NonDurableSubscriberError < Error; end

    # Raised when durability is enabled and a subscriber subscribes to the same event twice.
    class DuplicateSubscriberError < Error; end

    # Raised when looking up a subscriber that is not registered for an event.
    class UnknownSubscriberError < Error; end

    @durable = false
    @active_subscriptions = 0

    class << self
      # @return [Boolean] whether subscribers are registered for durable delivery
      attr_reader :durable

      # Sets whether subscribers are registered for durable delivery. Subscribers read
      # the flag when they subscribe, so it must be set before any subscription is made.
      #
      # @param [Boolean] value
      # @raise [ConfigurationError] if the value is not a boolean or a subscription is active
      def durable=(value)
        raise ConfigurationError, "Strata::Events.durable must be true or false, got #{value.inspect}" unless [ true, false ].include?(value)

        if @active_subscriptions.positive?
          raise ConfigurationError,
            "Strata::Events.durable cannot change while subscriptions are active; set it in an initializer " \
            "before any subscriber subscribes"
        end

        @durable = value
      end

      # @api private
      # Records how many subscriptions Strata::EventManager has active.
      #
      # @param [Integer] count
      def active_subscriptions=(count)
        @active_subscriptions = count
      end
    end
  end
end
