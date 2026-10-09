# frozen_string_literal: true

module Strata::Flows
  # Represents a sequence of question pages that iterates over a has_many
  # association on the flow record. Each child record is walked through the
  # same set of pages before the cursor advances to the next child.
  #
  # `scope:` optionally narrows the association — accepts a Symbol naming a
  # scope on the relation, or a Proc that receives the relation and returns
  # a filtered one. The filtered set drives traversal, completion, and child
  # lookup, so records outside the scope are skipped and cannot be edited.
  class Loop
    attr_accessor :name, :association, :scope, :pages

    def initialize(name, association: nil, scope: nil, pages: [])
      @name = name
      @association = association || name
      @scope = scope
      @pages = pages
    end

    def records_for(flow_record)
      base = flow_record.public_send(@association)
      apply_scope(base)
    end

    def record_class(flow_record)
      flow_record.class.reflect_on_association(@association).klass
    end

    def started?(flow_record)
      records_for(flow_record).any? do |child|
        @pages.any? { |page| page.completed?(child) }
      end
    end

    def completed?(flow_record)
      records_for(flow_record).all? do |child|
        @pages.all? { |page| page.completed?(child) }
      end
    end

    private

    def apply_scope(records)
      return records if @scope.nil?

      case @scope
      when Symbol then records.public_send(@scope)
      when Proc then @scope.call(records)
      else raise ArgumentError, "Loop scope must be a Symbol or Proc, got #{@scope.class}"
      end
    end
  end
end
