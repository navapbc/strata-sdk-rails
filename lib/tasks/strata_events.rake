# frozen_string_literal: true

require_relative "strata_task_helpers"

namespace :strata do
  namespace :events do
    extend StrataTaskHelpers

    desc "Publish a specified Strata event"
    task :publish_event, [ :event_name ] => [ :environment ] do |t, args|
      event_name = fetch_required_args!(args, :event_name).first

      Strata::EventManager.publish(event_name)

      Rails.logger.info "Event '#{event_name}' published. Subscriber failures are logged and reported via Rails.error."
    end

    desc "Publish a specified Strata event for a given case with a given ID"
    task :publish_case_event, [ :event_name, :case_class, :case_id ] => [ :environment ] do |t, args|
      event_name, case_class, case_id = *fetch_required_args!(args, :event_name, :case_class, :case_id)
      constantized_case_class = case_class.constantize

      kase = constantized_case_class.find(case_id)
      Strata::EventManager.publish(event_name, { kase: kase })

      Rails.logger.info "Event '#{event_name}' published for '#{case_class}' with ID '#{case_id}'. " \
        "Subscriber failures are logged and reported via Rails.error."
    end
  end
end
