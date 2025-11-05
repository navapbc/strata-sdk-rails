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

      def update_application_config
        application_rb_path = File.join(destination_root, "config/application.rb")
        content = File.read(application_rb_path)

        start_listening_call = "    #{business_process_name}BusinessProcess.start_listening_for_events"

        # Check for uncommented config.after_initialize block (not in comments)
        lines = content.lines
        block_start_index = nil
        block_indent = nil

        lines.each_with_index do |line, index|
          stripped = line.strip
          # Check if this is an uncommented config.after_initialize line
          if !stripped.start_with?("#") && stripped.match?(/\bconfig\.after_initialize\s+do(\s*\|[^|]*\|)?\s*$/)
            block_start_index = index
            block_indent = line[/^\s*/]
            break
          end
        end

        if block_start_index
          if content.include?(start_listening_call.strip)
            return
          end

          # Find the matching end for this block
          block_end_index = nil
          indent_level = 1

          lines[(block_start_index + 1)..-1].each_with_index do |line, rel_index|
            abs_index = block_start_index + 1 + rel_index
            stripped = line.strip

            # Skip comment lines
            next if stripped.start_with?("#")

            # Check for nested do blocks
            if stripped.match?(/\bdo(\s*\|[^|]*\|)?\s*$/)
              indent_level += 1
            elsif stripped == "end"
              indent_level -= 1
              if indent_level == 0
                block_end_index = abs_index
                break
              end
            end
          end

          if block_end_index
            # Insert the start_listening call before the closing end
            # start_listening_call already includes proper indentation (4 spaces)
            # but we need to match the block's indentation style
            call_without_indent = start_listening_call.strip
            insert_line = "#{block_indent}  #{call_without_indent}"
            lines.insert(block_end_index, insert_line)
            content = lines.map(&:chomp).join("\n") + "\n"
          else
            raise "Could not find matching end for config.after_initialize block"
          end
        else
          # Find the Application class and insert before its closing end
          # Work with full file content to properly calculate positions
          lines = content.lines
          class_start_line_index = nil
          application_end_line_index = nil

          # Find the Application class start
          lines.each_with_index do |line, index|
            if line.strip.start_with?("class Application") && line.include?("< Rails::Application")
              class_start_line_index = index
              break
            end
          end

          if class_start_line_index
            # Find the matching end for the Application class
            indent_level = 1
            class_indent = lines[class_start_line_index][/^\s*/]

            lines[(class_start_line_index + 1)..-1].each_with_index do |line, rel_index|
              abs_index = class_start_line_index + 1 + rel_index
              stripped = line.strip

              # Skip comment lines for indentation tracking
              next if stripped.start_with?("#")

              # Check for nested do blocks
              if stripped.match?(/\bdo(\s*\|[^|]*\|)?\s*$/)
                indent_level += 1
              elsif stripped == "end"
                indent_level -= 1
                if indent_level == 0
                  application_end_line_index = abs_index
                  break
                end
              end
            end

            if application_end_line_index
              # Insert before the Application class end
              before_lines = lines[0...application_end_line_index]
              after_lines = lines[application_end_line_index..-1]

              # Determine correct indentation (should match class body indentation)
              class_body_indent = "    " # Standard Rails Application class uses 4 spaces

              after_initialize_lines = [
                "",
                "#{class_body_indent}config.after_initialize do",
                "#{class_body_indent}  #{start_listening_call.strip}",
                "#{class_body_indent}end"
              ]

              new_lines = before_lines.map(&:chomp) + after_initialize_lines + after_lines.map(&:chomp)
              content = new_lines.join("\n") + "\n"
            else
              raise "Could not find matching end for Application class to insert config.after_initialize block"
            end
          else
            raise "Could not find Application class to insert config.after_initialize block"
          end
        end

        File.write(application_rb_path, content)
      end

      private

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
