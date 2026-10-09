# frozen_string_literal: true

module Strata::Flows
  # Represents an individual question page with a set of input fields.
  class QuestionPage
    include Rails.application.routes.url_helpers
    attr_accessor :name, :fields, :loop

    def initialize(name, if: nil, fields: nil, loop: nil)
      reserved_attributes = { if: }

      @name = name
      @if = reserved_attributes[:if]
      @fields = fields || [ @name.to_sym ]
      @loop = loop
    end

    def in_loop?
      @loop.present?
    end

    def needed?(record)
      @if.blank? || @if.call(record)
    end

    def completed?(record)
      record.valid?(@name.to_sym)
    end

    def edit_pathname
      in_loop? ? "edit_#{@loop.name}_#{@name}" : "edit_#{@name}"
    end

    def edit_path(flow_record, loop_record = nil)
      if in_loop?
        send(
          "#{edit_pathname}_#{flow_record.class.name.underscore}_#{@loop.association.to_s.singularize}_path",
          flow_record, loop_record
        )
      else
        send("#{edit_pathname}_#{flow_record.class.name.underscore}_path", flow_record)
      end
    end

    def update_pathname
      in_loop? ? "update_#{@loop.name}_#{@name}" : "update_#{@name}"
    end

    def update_path(flow_record, loop_record = nil)
      if in_loop?
        send(
          "#{update_pathname}_#{flow_record.class.name.underscore}_#{@loop.association.to_s.singularize}_path",
          flow_record, loop_record
        )
      else
        send("#{update_pathname}_#{flow_record.class.name.underscore}_path", flow_record)
      end
    end

    # Returns the list of permitted parameter keys for this page's fields,
    # expanding strata attributes into their component columns.
    #
    # @param record_klass [Class<ActiveRecord::Base>] a model class that defines strata attributes
    # @return [Array<Symbol, Hash>] flat parameter keys and multi-parameter hashes
    def attributes(record_klass)
      registry = record_klass.try(:strata_attributes_registry) || {}

      @fields.flat_map do |field|
        registry[field] || [ field ]
      end
    end
  end
end
