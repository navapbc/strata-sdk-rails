# frozen_string_literal: true

module Strata::Flows
  # Evaluates a task within the context of a given record and the current page.
  # When the current position is inside a Loop, the evaluator also carries the
  # active child record and the index within the loop's pages so traversal
  # methods can move both within the loop and out of it.
  class TaskEvaluator
    attr_accessor :task, :record, :current_page_idx, :loop_record, :loop_page_idx

    def initialize(task, record, current_page_idx, loop_record: nil, loop_page_idx: nil)
      @task = task
      @record = record
      @current_page_idx = current_page_idx
      @loop_record = loop_record
      @loop_page_idx = loop_page_idx
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

    def current_loop
      item = @task.pages[@current_page_idx]
      item.is_a?(Loop) ? item : nil
    end

    def in_loop?
      current_loop.present?
    end

    def current_page
      in_loop? ? current_loop.pages[@loop_page_idx] : @task.pages[@current_page_idx]
    end

    def update_path
      in_loop? ? current_page.update_path(@record, @loop_record) : current_page.update_path(@record)
    end

    # Path to the previous page, or nil if at the start of the task.
    def prev_path
      step(:backward)
    end

    # Path to the next page, or nil if at the end of the task.
    def next_path
      step(:forward)
    end

    private

    # If the cursor is inside a Loop, try to move within it first; otherwise
    # (or if the loop is exhausted) walk the task's outer pages.
    def step(direction)
      if in_loop?
        within = step_within_loop(direction)
        return within if within
      end

      walk_outer(@current_page_idx, direction)
    end

    # Move within the current Loop: first try an adjacent page on the active
    # child record, then fall through to the next child record's first
    # needed page. Returns nil when the loop has nothing more in that
    # direction.
    def step_within_loop(direction)
      loop_node = current_loop
      page = traverse(loop_node.pages, @loop_page_idx, direction)
             .find { |p| p.needed?(@loop_record) }
      return page.edit_path(@record, @loop_record) if page

      records = loop_node.records_for(@record)
      current_idx = records.find_index(@loop_record)
      return nil unless current_idx

      enter_loop(loop_node, traverse(records, current_idx, direction), direction)
    end

    # Walk the task's top-level pages from `starting_idx` and return the
    # path of the first item we can enter.
    def walk_outer(starting_idx, direction)
      traverse(@task.pages, starting_idx, direction).each do |item|
        path = enter(item, direction)
        return path if path
      end
      nil
    end

    # Enter a single top-level item: a QuestionPage's edit path if needed,
    # or the first reachable page of a Loop.
    def enter(item, direction)
      if item.is_a?(Loop)
        enter_loop(item, ordered(item.records_for(@record), direction), direction)
      elsif item.needed?(@record)
        item.edit_path(@record)
      end
    end

    # Walk `records` (already ordered for the direction) and return the
    # edit path of the first child whose first needed page exists.
    def enter_loop(loop_node, records, direction)
      records.each do |child|
        page = ordered(loop_node.pages, direction).find { |p| p.needed?(child) }
        return page.edit_path(@record, child) if page
      end
      nil
    end

    # Elements of `arr` adjacent to `idx`, ordered so the nearest comes
    # first: items after `idx` forward, items before `idx` (reversed) backward.
    def traverse(arr, idx, direction)
      direction == :forward ? (arr[(idx + 1)..] || []) : arr.first(idx).reverse
    end

    # `arr` in iteration order for the direction (reversed when backward).
    def ordered(arr, direction)
      direction == :forward ? arr : arr.reverse
    end
  end
end
