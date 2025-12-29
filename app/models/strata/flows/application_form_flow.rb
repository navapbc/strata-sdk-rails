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

      # Returns all routes that can be generated when used in
      # combination with ApplicationFormController
      def generated_routes
        tasks.flat_map(&:pages).flat_map do |page|
          [ page.edit_pathname, page.update_pathname ]
        end
      end

      # Defines a new task block
      def task(task_name, &block)
        @current_task = Task.new(task_name)
        tasks.push(@current_task)
        block.call
        @current_task = nil
      end

      # Defines an individual question page.
      # If no fields are provided, we assume that the page
      # has one field which matches the name of the page.
      def question_page(page_name, fields: nil)
        page = QuestionPage.new(page_name, fields:)
        @current_task.pages.push(page)
        contexts.push(page_name)
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

      def find_page_and_task_by_action(action)
        tasks.each do |task|
          task.pages.each_with_index do |page, page_idx|
            # Search for the current page based on the request action
            if [ page.edit_pathname.to_sym, page.update_pathname.to_sym ].include?(action.to_sym)
              return page, TaskEvaluator.new(task, flow_record, page_idx)
            end
          end
        end

        return nil, nil
      end

      def to_mermaid
        diagram = "flowchart TD\n"

        tasks.each do |task|
          task.pages.each do |page|
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
          if task.pages.length < 2
            diagram += "    #{task.pages.first.name}\n"
          else
            task.pages.each_cons(2) do |a, b|
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
