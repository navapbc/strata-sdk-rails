# frozen_string_literal: true

module Strata::Flows
  # Primary concern for defining the flow of a multi-page form.
  #
  # @example
  #   class LeaveApplicationFlow
  #     task :personal_information do
  #       question_page :name, fields: [ :applicant_name_first, :applicant_name_last ]
  #       question_page :date_of_birth
  #       question_page :tax_identifier
  #     end
  #     task :leave_details do
  #       question_page :leave_type
  #       question_page :leave_dates
  #       question_page :supporting_documents, if: ->(app) { app.leave_type_medical? }
  #     end
  #     task :prior_employment do
  #       loop :prior_employer, association: :prior_employers do
  #         question_page :business_name
  #         question_page :role
  #       end
  #     end
  #   end
  module ApplicationFormFlow
    extend ActiveSupport::Concern
    include Rails.application.routes.url_helpers

    class_methods do
      attr_accessor :tasks
      attr_accessor :contexts
      attr_accessor :start_pathname
      attr_accessor :end_pathname

      def tasks
        @tasks ||= []
      end

      def contexts
        @contexts ||= []
      end

      def pages
        tasks.flat_map(&:pages)
      end

      # Returns the flat sequence of QuestionPages across the flow, with each
      # Loop expanded in place into its enclosed pages.
      def all_pages
        tasks.flat_map do |task|
          task.pages.flat_map do |item|
            item.is_a?(Loop) ? item.pages : [ item ]
          end
        end
      end

      # Returns all routes that can be generated when used in
      # combination with ApplicationFormController
      def generated_routes
        all_pages.flat_map do |page|
          [ page.edit_pathname, page.update_pathname ]
        end
      end

      # Validates that an explicit depends_on array only references existing task names.
      def validate_depends_on!(depends_on)
        return unless depends_on.is_a?(Array)

        existing_names = tasks.map(&:name)
        invalid = depends_on - existing_names
        return unless invalid.any?

        raise ArgumentError, "depends_on references unknown task(s): #{invalid.join(', ')}"
      end

      # Defines a new task block
      def task(task_name, depends_on: nil, &block)
        validate_depends_on!(depends_on)

        @current_task = Task.new(task_name, depends_on: depends_on)
        tasks.push(@current_task)
        block.call
        @current_task = nil
      end

      # Defines an individual question page.
      # If no fields are provided, we assume that the page
      # has one field which matches the name of the page.
      def question_page(page_name, if: nil, fields: nil)
        page = QuestionPage.new(page_name, if:, fields:, loop: @current_loop)
        if @current_loop.present?
          @current_loop.pages.push(page)
        else
          @current_task.pages.push(page)
        end
        contexts.push(page_name)
        validate_unique_action_names!
      end

      # Defines a loop over a has_many association on the flow record.
      # When association: is omitted, it defaults to the loop name.
      # `scope:` optionally narrows the association — accepts a Symbol naming
      # a scope on the relation, or a Proc that receives and returns a relation.
      def loop(loop_name, association: nil, scope: nil, &block)
        @current_loop = Loop.new(loop_name, association: association, scope: scope)
        @current_task.pages.push(@current_loop)
        block.call
        @current_loop = nil
      end

      # A start page to return to when exiting out of a
      # task block or collection of question pages.
      def start_page(path)
        if @start_pathname.present?
          raise StandardError, "Start page cannot be configured multiple times"
        end

        @start_pathname = path
      end

      # An end page to continue to after completing all
      # of the questions within the flow.
      def end_page(path)
        if @end_pathname.present?
          raise StandardError, "End page cannot be configured multiple times"
        end

        @end_pathname = path
      end

      def find_page_and_task_by_action(flow_record, action, id_param = nil)
        action_sym = action.to_sym

        tasks.each do |task|
          task.pages.each_with_index do |item, page_idx|
            if item.is_a?(Loop)
              item.pages.each_with_index do |loop_page, loop_page_idx|
                next unless [ loop_page.edit_pathname.to_sym, loop_page.update_pathname.to_sym ].include?(action_sym)

                loop_record = resolve_loop_record(item, flow_record, id_param)
                return loop_page, TaskEvaluator.new(
                  task, flow_record, page_idx,
                  loop_record: loop_record, loop_page_idx: loop_page_idx
                )
              end
            elsif [ item.edit_pathname.to_sym, item.update_pathname.to_sym ].include?(action_sym)
              return item, TaskEvaluator.new(task, flow_record, page_idx)
            end
          end
        end

        return nil, nil
      end

      def to_mermaid
        diagram = "flowchart TD\n"

        tasks.each do |task|
          task.pages.each do |page|
            next if page.is_a?(Loop)
            node_name = page.name
            fields = page.fields.flat_map do |field|
              if field.is_a?(Hash)
                field.keys.map do |key|
                  if field[key].length > 0
                    "<div style=\"border: 1px solid black; padding: 4px 8px\"><i style=\"text-decoration: underline\">#{key}</i><br>#{field[key].flatten.join("<br>")}</div>"
                  else
                    key
                  end
                end
              else
                field
              end
            end
            node_text = [ "<b>#{page.name}</b>", *fields ].join("<br>")
            diagram += "  #{node_name}[#{node_text}]\n"
          end

          diagram += "  subgraph t_#{task.name}[Task: #{task.name}]\n"
          rendered_pages = task.pages.reject { |p| p.is_a?(Loop) }
          if rendered_pages.length < 2
            diagram += "    #{rendered_pages.first.name}\n" if rendered_pages.first
          else
            rendered_pages.each_cons(2) do |a, b|
              diagram += "    #{a.name} --> #{b.name}\n"
            end
          end
          diagram += "  end\n"
        end

        tasks.each_cons(2) do |a, b|
          diagram += "t_#{a.name} --> t_#{b.name}\n"
        end

        diagram
      end

      private

      def resolve_loop_record(loop_node, flow_record, id_param)
        return nil unless id_param

        loop_node.records_for(flow_record).find(id_param)
      end

      def validate_unique_action_names!
        pathnames = all_pages.flat_map { |p| [ p.edit_pathname, p.update_pathname ] }
        duplicates = pathnames.tally.select { |_, count| count > 1 }.keys
        return if duplicates.empty?

        raise ArgumentError, "duplicate action name(s) in flow: #{duplicates.join(', ')}"
      end
    end

    # === Instance Methods =====

    attr_accessor :record

    def initialize(record)
      @record = record
    end

    def completed?
      tasks.all? { |task| task.completed?(@record) }
    end

    def tasks
      self.class.tasks
    end

    def pages
      self.class.pages
    end

    def task_counter(task)
      tasks.find_index(task)
    end

    # Evaluates whether the given depends_on constraint is satisfied.
    # Returns true if depends_on is nil, otherwise checks that all
    # referenced tasks (or all tasks for :all) are completed.
    def dependencies_met?(depends_on, exclude: nil)
      return true if depends_on.nil?

      dependent_tasks = if depends_on == :all
        exclude ? tasks.reject { |t| t.name == exclude } : tasks
      else
        tasks.select { |t| depends_on.include?(t.name) }
      end

      dependent_tasks.all? { |t| t.completed?(@record) }
    end

    # Returns the full, parameterized path to the start_page
    def start_path
      if self.class.start_pathname.present?
        send(self.class.start_pathname, @record)
      else
        send("#{record.class.name.underscore}_path", @record)
      end
    end

    # Returns the full, parameterized path to the end_page
    def end_path
      send("#{self.class.end_pathname}_#{record.class.name.underscore}_path", @record)
    end
  end
end
