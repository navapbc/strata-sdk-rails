# frozen_string_literal: true

module Strata
  # Service layer module that provides a unified interface for task management.
  # This module implements the Service Locator pattern to provide a configurable
  # task service implementation. By default, it uses the Database adapter, but
  # can be configured to use other task service implementations.
  #
  # @example
  #   task_service = Strata::TaskService.get
  #   task_service.create_task(kase)
  #
  module TaskService
    mattr_accessor :service

    # Sets the task service implementation to be used.
    #
    # @param service [Object] The task service implementation to use.
    #   Must implement the required task service interface.
    # @return [Object] The service that was set
    def self.set(service)
      raise ArgumentError, "Service must be a subclass of TaskService::Base" unless service.nil? || service.is_a?(Strata::TaskService::Base)
      self.service = service
    end

    # Gets the current task service implementation.
    # If no service has been set, initializes and returns the default Database adapter.
    #
    # @return [Object] The current task service implementation
    # @note Currently defaults to {Strata::TaskService::Database} if no service is set.
    #   Future versions may determine the service based on environment configuration.
    def self.get
      if service.nil?
        # Other ideas for adapters: asana, jira, salesforce, trello
        # In the future, we can determine the task service based on the environment
        # e.g. something like task_service_name = ENV["TASK_SERVICE"] || "Strata::TaskService::Database"
        # self.service = task_service_name.constantize.new
        set(Strata::TaskService::Database.new)
      end

      service
    end
  end
end
