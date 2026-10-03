# frozen_string_literal: true

module Strata::Flows
  # Represents a set of related questions as a task within a flow.
  class Task
    attr_accessor :name, :pages, :depends_on

    def initialize(name, depends_on: nil, pages: [])
      @name = name
      @depends_on = depends_on
      @pages = pages
    end

    def started?(record)
      @pages.any? do |item|
        item.is_a?(Loop) ? item.started?(record) : item.completed?(record)
      end
    end

    def completed?(record)
      @pages.all? do |item|
        item.completed?(record)
      end
    end

    def dependencies_met?(flow)
      flow.dependencies_met?(@depends_on, exclude: @name)
    end

    # Returns the current workable page if in-progress, or the first page otherwise.
    def path(record)
      return nil if @pages.empty?

      if !started?(record) || completed?(record)
        first_path(record)
      else
        first_incomplete_path(record)
      end
    end

    private

    def first_path(record)
      @pages.each do |item|
        path = enter_forward(item, record)
        return path if path
      end
      nil
    end

    def first_incomplete_path(record)
      @pages.each do |item|
        if item.is_a?(Loop)
          item.records_for(record).each do |child|
            incomplete = item.pages.find { |p| !p.completed?(child) }
            return incomplete.edit_path(record, child) if incomplete
          end
        elsif !item.completed?(record)
          return item.edit_path(record)
        end
      end
      nil
    end

    def enter_forward(item, record)
      if item.is_a?(Loop)
        first_child = item.records_for(record).first
        return nil unless first_child
        first_page = item.pages.find { |p| p.needed?(first_child) }
        first_page&.edit_path(record, first_child)
      else
        item.needed?(record) ? item.edit_path(record) : nil
      end
    end
  end
end
