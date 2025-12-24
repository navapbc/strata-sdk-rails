# frozen_string_literal: true

module Strata::Flows
  # Represents a set of related questions as a task within a flow.
  class Task
    attr_accessor :name, :pages

    def initialize(name, pages: [])
      @name = name
      @pages = pages
    end

    def started?(record)
      @pages.any? { |page| page.completed?(record) }
    end

    def completed?(record)
      @pages.all? { |page| page.completed?(record) }
    end

    # Returns the current workable page if in-progress, or the first page otherwise.
    def path(record)
      return nil if @pages.empty?

      if !started?(record) || completed?(record)
        @pages.first.edit_path(record)
      else
        @pages.find { |page| !page.completed?(record) }.edit_path(record)
      end
    end
  end
end
