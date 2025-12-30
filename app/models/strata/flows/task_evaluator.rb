# frozen_string_literal: true

module Strata::Flows
  # Evaluates a task within the context of a given record and the current page.
  class TaskEvaluator
    attr_accessor :task, :record, :current_page_idx

    def initialize(task, record, current_page_idx)
      @task = task
      @record = record
      @current_page_idx = current_page_idx
    end

    def started?
      @task.started?(record)
    end

    def completed?
      @task.completed?(record)
    end

    def pages
      @task.pages
    end

    def path
      @task.path
    end

    def current_page
      pages[@current_page_idx]
    end

    def prev_path
      next_page_idx = @current_page_idx - 1

      while next_page_idx >= 0
        page = pages[next_page_idx]
        return page.edit_path(@record) if page.needed?(@record)
        next_page_idx -= 1
      end

      nil
    end

    def update_path
      current_page.update_path(@record)
    end

    def next_path
      next_page_idx = @current_page_idx + 1

      while next_page_idx <= pages.length - 1
        page = pages[next_page_idx]
        return page.edit_path(@record) if page.needed?(@record)
        next_page_idx += 1
      end

      nil
    end
  end
end
