# frozen_string_literal: true

require_relative "strata_task_helpers"

namespace :strata do
  namespace :events do
    extend StrataTaskHelpers

    desc "Publish a specified Strata event"
    task :publish_event, [ :event_name ] => [ :environment ] do |t, args|
      event_name = fetch_required_args!(args, :event_name).first

      failures = Strata::EventManager.publish_reporting_failures(event_name)
      abort_on_subscriber_failures!("Event '#{event_name}'", failures)

      Rails.logger.info "Event '#{event_name}' published."
    end

    desc "Publish a specified Strata event for a given case with a given ID"
    task :publish_case_event, [ :event_name, :case_class, :case_id ] => [ :environment ] do |t, args|
      event_name, case_class, case_id = *fetch_required_args!(args, :event_name, :case_class, :case_id)
      constantized_case_class = case_class.constantize

      kase = constantized_case_class.find(case_id)
      failures = Strata::EventManager.publish_reporting_failures(event_name, { kase: kase })
      abort_on_subscriber_failures!("Event '#{event_name}' for '#{case_class}' with ID '#{case_id}'", failures)

      Rails.logger.info "Event '#{event_name}' published for '#{case_class}' with ID '#{case_id}'."
    end
  end
end
