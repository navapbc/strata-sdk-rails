# frozen_string_literal: true

require "rails/generators"

# Generator for creating business process files with standardized templates
module Strata
  module Generators
    # Generator for creating business process files with standardized templates
    class BusinessProcessGenerator < Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      class_option :case, type: :string, desc: "(optional) Case class name. Ex: MedicaidCase"
      class_option :"application-form", type: :string, desc: "(optional) Application form name. Ex: MedicaidApplicationForm"
      class_option :"skip-application-form", type: :boolean, default: false, desc: "Skip application form generation check"
      class_option :"force-application-form", type: :boolean, default: false, desc: "Generate application form without prompting"

      APPLICATION_FORM_SUFFIX = "ApplicationForm"

      def check_application_form_exists
        return if options[:"skip-application-form"]
        return if @application_form_checked

        @application_form_checked = true
        app_form_class = application_form_name
        unless app_form_class.safe_constantize.present?
          if should_generate_application_form?(app_form_class)
            base_name = app_form_class.end_with?(APPLICATION_FORM_SUFFIX) ? app_form_class[0...-APPLICATION_FORM_SUFFIX.length] : app_form_class
            generate("strata:application_form", base_name)
          end
        end
      end

      def create_business_process_file
        full_file_path = File.join(destination_root, business_process_file_path)
        if File.exist?(full_file_path)
          raise "Business process file already exists at #{business_process_file_path}"
        end

        check_application_form_exists
        template "business_process.rb.tt", business_process_file_path
      end

      # Updates the host application's config/application.rb to register the business process
      # for event listening. This ensures the business process starts listening for events
      def update_application_config
        application_rb_path = File.join(destination_root, "config/application.rb")
        content = File.read(application_rb_path)
        start_listening_call = "    #{business_process_name}BusinessProcess.start_listening_for_events"

        # Early return if already configured (makes generator idempotent)
        return if content.include?(start_listening_call.strip)

        # Try to find existing uncommented config.after_initialize block
        existing_block_index = find_existing_after_initialize_block(content)

        if existing_block_index
          # Insert into existing block to avoid creating multiple config.after_initialize blocks
          content = insert_into_existing_block(content, existing_block_index, start_listening_call)
        else
          # No existing block found, create new one inside Application class
          content = create_new_after_initialize_block(content, start_listening_call)
        end

        File.write(application_rb_path, content)
      end

      private

      # Finds an uncommented config.after_initialize block in the content.
      def find_existing_after_initialize_block(content)
        lines = content.lines
        lines.each_with_index do |line, index|
          stripped = line.strip
          # Check if this is an uncommented config.after_initialize line
          # The regex \b ensures we match whole words, not partial matches
          if !stripped.start_with?("#") && stripped.match?(/\bconfig\.after_initialize\s+do(\s*\|[^|]*\|)?\s*$/)
            return index
          end
        end
        nil
      end

      # Inserts the start_listening call into an existing config.after_initialize block.
      def insert_into_existing_block(content, block_start_index, start_listening_call)
        lines = content.lines
        # Extract the indentation from the block start line to match the block's style
        block_indent = lines[block_start_index][/^\s*/]

        # Find the matching end for this block (handles nested blocks correctly)
        block_end_index = find_matching_end(lines, block_start_index, 1)
        raise "Could not find matching end for config.after_initialize block" unless block_end_index

        # Insert the start_listening call before the closing end
        call_without_indent = start_listening_call.strip
        insert_line = "#{block_indent}  #{call_without_indent}"
        lines.insert(block_end_index, insert_line)

        # Normalize newlines to prevent formatting issues
        lines.map(&:chomp).join("\n") + "\n"
      end

      # Creates a new config.after_initialize block inside the Application class.
      def create_new_after_initialize_block(content, start_listening_call)
        lines = content.lines

        # Find the Application class start - must be inside the class, not outside
        class_start_index = find_application_class_start(lines)
        raise "Could not find Application class to insert config.after_initialize block" unless class_start_index

        # Find the matching end for the Application class
        application_end_index = find_matching_end(lines, class_start_index, 1)
        raise "Could not find matching end for Application class to insert config.after_initialize block" unless application_end_index

        # Split the file into lines before and after the Application class end
        before_lines = lines[0...application_end_index].map(&:chomp)
        after_lines = lines[application_end_index..-1].map(&:chomp)

        # Standard Rails Application class uses 4 spaces for indentation
        class_body_indent = "    "
        after_initialize_lines = [
          "", # Empty line before the block for readability
          "#{class_body_indent}config.after_initialize do",
          "#{class_body_indent}  #{start_listening_call.strip}", # 2 spaces for block body
          "#{class_body_indent}end"
        ]

        # Combine all lines and normalize newlines
        new_lines = before_lines + after_initialize_lines + after_lines
        new_lines.join("\n") + "\n"
      end

      # Finds the line index where the Application class starts.
      def find_application_class_start(lines)
        lines.each_with_index do |line, index|
          if line.strip.start_with?("class Application") && line.include?("< Rails::Application")
            return index
          end
        end
        nil
      end

      # Finds the matching 'end' for a block by tracking nested blocks via indent level.
      def find_matching_end(lines, start_index, initial_indent_level)
        indent_level = initial_indent_level

        lines[(start_index + 1)..-1].each_with_index do |line, rel_index|
          abs_index = start_index + 1 + rel_index
          stripped = line.strip

          # Skip comment lines for indentation tracking
          next if stripped.start_with?("#")

          # Check for nested do blocks (with optional block parameters)
          if stripped.match?(/\bdo(\s*\|[^|]*\|)?\s*$/)
            indent_level += 1
          elsif stripped == "end"
            indent_level -= 1
            # When indent_level reaches 0, we've found the matching 'end'
            return abs_index if indent_level == 0
          end
        end

        nil
      end

      def business_process_name
        # Remove "BusinessProcess" suffix if present to avoid duplication in class name
        base_name = name.gsub(/BusinessProcess$/i, "")
        base_name.classify
      end

      def file_name
        # Remove "BusinessProcess" suffix if present to avoid duplication
        base_name = name.gsub(/BusinessProcess$/i, "")
        base_name.underscore
      end

      def business_process_file_path
        "app/business_processes/#{file_name}_business_process.rb"
      end

      def case_name
        options[:case] || "#{business_process_name}Case"
      end

      def application_form_name
        options[:"application-form"] || "#{business_process_name}ApplicationForm"
      end

      def should_generate_application_form?(app_form_class)
        options[:"force-application-form"] || yes?("Application form #{app_form_class} does not exist. Generate it? (y/n)")
      end
    end
  end
end
