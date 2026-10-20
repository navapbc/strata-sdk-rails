# frozen_string_literal: true

# Sets Strata::Events.durable for the duration of a block.
#
# The flag can only be set while no subscriptions are active, and the dummy app
# subscribes PassportBusinessProcess at boot, so this stops it first and
# restarts it afterward. Subscriptions made inside the block are removed.
module DurableEventsHelpers
  def with_durable_events(durable = true)
    PassportBusinessProcess.stop_listening_for_events
    Strata::Events.durable = durable
    yield
  ensure
    Strata::EventManager.unsubscribe_all
    Strata::Events.durable = false
    PassportBusinessProcess.start_listening_for_events
  end
end
