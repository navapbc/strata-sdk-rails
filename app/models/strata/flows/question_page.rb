# frozen_string_literal: true

module Strata::Flows
  # Represents an individual question page with a set of input fields.
  class QuestionPage
    include Rails.application.routes.url_helpers
    attr_accessor :name, :fields

    def initialize(name, if:, fields: nil)
      reserved_attributes = { if: }

      @name = name
      @if = reserved_attributes[:if]
      @fields = fields || [ @name.to_sym ]
    end

    def needed?(record)
      @if.blank? || @if.call(record)
    end

    def completed?(record)
      record.valid?(@name)
    end

    def edit_pathname
      "edit_#{@name}"
    end

    def edit_path(record)
      send("#{edit_pathname}_#{record.class.name.underscore}_path", record)
    end

    def update_pathname
      "update_#{@name}"
    end

    def update_path(record)
      send("#{update_pathname}_#{record.class.name.underscore}_path", record)
    end
  end
end
