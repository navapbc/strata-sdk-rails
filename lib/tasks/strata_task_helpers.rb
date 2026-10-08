# frozen_string_literal: true

# Shared helper methods for Strata rake tasks
module StrataTaskHelpers
  def fetch_required_args!(args, *required_keys)
    missing = required_keys.select { |k| args[k].blank? }
    if missing.any?
      verb = missing.size == 1 ? "is" : "are"
      raise "Error: #{missing.to_sentence} #{verb} required"
    end

    required_keys.map { |k| args[k] }
  end

  # Exits non-zero, listing each failure, when EventManager.publish_reporting_failures returns failed subscribers.
  def abort_on_subscriber_failures!(description, failures)
    return if failures.empty?

    lines = failures.map { |failure| "  #{failure[:subscriber]}: #{failure[:error].class}: #{failure[:error].message}" }
    abort "#{description} published, but #{failures.size} subscriber(s) failed and were rolled back:\n#{lines.join("\n")}"
  end
end
