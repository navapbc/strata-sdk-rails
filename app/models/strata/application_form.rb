# frozen_string_literal: true

module Strata
  # ApplicationForm is the base class for all form models in the Strata SDK.
  # It provides functionality for tracking form status (in_progress/submitted)
  # and prevents modification of submitted forms.
  #
  # Form models should inherit from this class and add their specific fields.
  #
  # @example Creating a form model
  #   class MyApplicationForm < Strata::ApplicationForm
  #     attribute :name, :string
  #     attribute :email, :string
  #   end
  #
  # Key features:
  # - Tracks form status (in_progress/submitted)
  # - Prevents modification of submitted forms
  # - Publishes events when created and submitted
  #
  class ApplicationForm < ApplicationRecord
    self.abstract_class = true

    include Strata::Attributes
    include Strata::Determinable

    define_model_callbacks :submit, only: [ :before, :after ]

    attribute :status, :integer, default: 0
    protected attr_writer :status
    enum :status, in_progress: 0, submitted: 1

    attribute :user_id, :uuid
    attribute :submitted_at, :datetime

    # Returns the base attributes required for all application forms
    # Used by generators to ensure all application forms have the necessary attributes
    # NOTE: This method must be updated if additional attributes are added to this abstract model
    #
    # @return [Array<String>] Array of attribute definitions in "name:type" format
    class << self
      def base_attributes_for_generator
        [
          "user_id:uuid",
          "status:integer",
          "submitted_at:datetime"
        ]
      end
    end

    after_create :publish_created
    before_update :prevent_changes_if_submitted, if: :was_submitted?

    # Submits the application form, changing its status to 'submitted'
    # and publishing a submission event.
    #
    # This method should be called when a user submits the form.
    # After submission, the form can no longer be modified.
    #
    # Validates the form with the :submit context before proceeding.
    # If validation fails, the submission is aborted and returns false.
    #
    # @return [Boolean] True if the submission was successful
    def submit_application
      # First run validations with submit context
      return false unless valid?(:submit)

      # Then proceed with callbacks as before
      success = run_callbacks :submit do
        Rails.logger.debug "Submitting application with ID: #{id}"
        self[:status] = :submitted
        self[:submitted_at] = Time.current
        save!
        publish_submitted
      end
      success != false
    end

    protected

    # Returns the event payload for publishing events related to this form.
    #
    # @return [Hash] Payload with application_form_id
    def event_payload
      payload = { application_form_id: id }
      payload[:submitted_at] = submitted_at if submitted_at.present?
      payload
    end

    private

    def was_submitted?
      status_was == "submitted"
    end

    def prevent_changes_if_submitted
      errors.add(:base, "Cannot modify a submitted application")
      throw :abort
    end

    def publish_created
      Rails.logger.debug "Publishing event #{self.class.name}Created for application with ID: #{id}"
      Strata::EventManager.publish("#{self.class.name}Created", self.event_payload)
    end

    def publish_submitted
      Rails.logger.debug "Publishing event #{self.class.name}Submitted for application with ID: #{id}"
      Strata::EventManager.publish("#{self.class.name}Submitted", self.event_payload)
    end
  end
end
