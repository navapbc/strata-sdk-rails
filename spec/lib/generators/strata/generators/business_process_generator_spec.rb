# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/business_process/business_process_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::BusinessProcessGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([ 'Test' ], options.merge(quiet: true), destination_root: destination_root) }
  let(:options) { { case: case_option, "application-form": app_form_option } }
  let(:case_option) { nil }
  let(:app_form_option) { nil }

  before do
    FileUtils.mkdir_p("#{destination_root}/app/business_processes")
    FileUtils.mkdir_p("#{destination_root}/config")

    File.write("#{destination_root}/config/application.rb", <<~RUBY)
      require_relative "boot"

      require "rails/all"

      Bundler.require(*Rails.groups)

      module Dummy
        class Application < Rails::Application
          config.load_defaults Rails::VERSION::STRING.to_f

          config.generators do |g|
            g.factory_bot suffix: "factory"
          end
        end
      end
    RUBY
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "with basic name only" do
    before do
      allow(generator).to receive(:generate).and_call_original
      allow(generator).to receive(:yes?).and_return(false)
      generator.invoke_all
    end

    it "creates business process file with correct naming" do
      business_process_file = "#{destination_root}/app/business_processes/test_business_process.rb"
      expect(File.exist?(business_process_file)).to be true
    end

    it "updates application.rb with start_listening_for_events call" do
      content = File.read("#{destination_root}/config/application.rb")

      expected = <<~RUBY
        require_relative "boot"

        require "rails/all"

        Bundler.require(*Rails.groups)

        module Dummy
          class Application < Rails::Application
            config.load_defaults Rails::VERSION::STRING.to_f

            config.generators do |g|
              g.factory_bot suffix: "factory"
            end

            config.after_initialize do
              TestBusinessProcess.start_listening_for_events
            end
          end
        end
      RUBY

      # rstrip to remove trailing newline
      expect(content.rstrip).to eq(expected.rstrip)
    end
  end

  describe "with custom case option" do
    let(:case_option) { Faker::Name.first_name }

    before do
      allow(generator).to receive(:generate).and_call_original
      allow(generator).to receive(:yes?).and_return(false)
      generator.invoke_all
    end

    it "uses custom case name" do
      business_process_file = "#{destination_root}/app/business_processes/test_business_process.rb"
      content = File.read(business_process_file)
      expect(content).to include("class TestBusinessProcess < Strata::BusinessProcess")
      expect(content).to include("def self.case_class")
    end
  end

  describe "when name already includes BusinessProcess suffix" do
    let(:generator) { described_class.new([ 'TestBusinessProcess' ], options.merge(quiet: true), destination_root: destination_root) }

    before do
      allow(generator).to receive(:generate).and_call_original
      allow(generator).to receive(:yes?).and_return(false)
      generator.invoke_all
    end

    it "does not duplicate BusinessProcess in class name" do
      business_process_file = "#{destination_root}/app/business_processes/test_business_process.rb"
      content = File.read(business_process_file)
      expect(content).to include("class TestBusinessProcess < Strata::BusinessProcess")
      expect(content).not_to include("TestBusinessProcessBusinessProcess")
    end

    it "does not duplicate BusinessProcess in file name" do
      business_process_file = "#{destination_root}/app/business_processes/test_business_process.rb"
      expect(File.exist?(business_process_file)).to be true
      expect(File.exist?("#{destination_root}/app/business_processes/test_business_process_business_process.rb")).to be false
    end
  end

  describe "with custom case and application_form options" do
    let(:case_option) { Faker::Name.first_name }
    let(:app_form_option) { Faker::Name.first_name }

    before do
      allow(generator).to receive(:generate).and_call_original
      allow(generator).to receive(:yes?).and_return(false)
      generator.invoke_all
    end

    it "uses custom case and application form names" do
      business_process_file = "#{destination_root}/app/business_processes/test_business_process.rb"
      content = File.read(business_process_file)
      expect(content).to include("class TestBusinessProcess < Strata::BusinessProcess")
      expect(content).to include("def self.case_class")

      expect(content).to include("def self.case_class")
      expect(content).to include("transition('submit_application', '#{app_form_option}Submitted', 'example_1')")
    end
  end

  describe "when business process file already exists" do
    before do
      File.write("#{destination_root}/app/business_processes/test_business_process.rb", "# existing file")
      allow(generator).to receive(:generate).and_call_original
      allow(generator).to receive(:yes?).and_return(false)
    end

    it "raises an error" do
      expect {
        generator.invoke_all
      }.to raise_error(/Business process file already exists/)
    end
  end

  describe "when config.after_initialize already exists" do
    before do
      File.write("#{destination_root}/config/application.rb", <<~RUBY)
        module Dummy
          class Application < Rails::Application
            config.after_initialize do
              # existing code
            end
          end
        end
      RUBY

      generator_with_existing_config = described_class.new([ 'Test' ], { quiet: true }, destination_root: destination_root)
      allow(generator_with_existing_config).to receive(:generate).and_call_original
      allow(generator_with_existing_config).to receive(:yes?).and_return(false)
      generator_with_existing_config.invoke_all
    end

    it "appends to existing after_initialize block" do
      content = File.read("#{destination_root}/config/application.rb")

      expected = <<~RUBY
        module Dummy
          class Application < Rails::Application
            config.after_initialize do
              # existing code
              TestBusinessProcess.start_listening_for_events
            end
          end
        end
      RUBY

      # rstrip to remove trailing newline
      expect(content.rstrip).to eq(expected.rstrip)
    end
  end

  describe "when config.after_initialize is commented out" do
    before do
      File.write("#{destination_root}/config/application.rb", <<~RUBY)
        module Dummy
          class Application < Rails::Application
            config.load_defaults Rails::VERSION::STRING.to_f

            # config.after_initialize do
            #   OldBusinessProcess.start_listening_for_events
            # end
          end
        end
      RUBY

      generator_with_commented_config = described_class.new([ 'Test' ], { quiet: true }, destination_root: destination_root)
      allow(generator_with_commented_config).to receive(:generate).and_call_original
      allow(generator_with_commented_config).to receive(:yes?).and_return(false)
      generator_with_commented_config.invoke_all
    end

    it "creates new uncommented config.after_initialize block" do
      content = File.read("#{destination_root}/config/application.rb")

      # Verify new uncommented block exists
      expect(content).to match(/^\s+config\.after_initialize do/)
      expect(content).to include("TestBusinessProcess.start_listening_for_events")

      # Verify commented block is preserved
      expect(content).to include("# config.after_initialize do")
      expect(content).to include("#   OldBusinessProcess.start_listening_for_events")

      # Verify the uncommented block is inside Application class (before closing end)
      lines = content.lines
      app_class_line = lines.find_index { |l| l.include?("class Application") }
      app_class_end_line = nil
      indent_level = 0

      lines[(app_class_line + 1)..-1].each_with_index do |line, idx|
        stripped = line.strip
        next if stripped.start_with?("#")
        if stripped.match?(/\bdo(\s*\|[^|]*\|)?\s*$/)
          indent_level += 1
        elsif stripped == "end"
          indent_level -= 1
          if indent_level == 0
            app_class_end_line = app_class_line + 1 + idx
            break
          end
        end
      end

      config_block_line = lines.find_index { |l| l.match?(/^\s+config\.after_initialize do/) && !l.strip.start_with?("#") }
      expect(config_block_line).to be > app_class_line
      expect(app_class_end_line).not_to be_nil, "Could not find Application class end"
      expect(config_block_line).to be < app_class_end_line if app_class_end_line
    end
  end

  describe "when start_listening_for_events already exists" do
    before do
      File.write("#{destination_root}/config/application.rb", <<~RUBY)
        require_relative "boot"

        require "rails/all"

        Bundler.require(*Rails.groups)

        module Dummy
          class Application < Rails::Application
            config.load_defaults Rails::VERSION::STRING.to_f

            config.after_initialize do
              TestBusinessProcess.start_listening_for_events
            end
          end
        end
      RUBY

      generator_with_duplicate = described_class.new([ 'Test' ], { quiet: true }, destination_root: destination_root)
      allow(generator_with_duplicate).to receive(:generate).and_call_original
      allow(generator_with_duplicate).to receive(:yes?).and_return(false)
      generator_with_duplicate.invoke_all
    end

    it "does not duplicate the call" do
      content = File.read("#{destination_root}/config/application.rb")
      occurrences = content.scan(/TestBusinessProcess\.start_listening_for_events/).length
      expect(occurrences).to eq(1)
    end
  end

  describe "application form generation" do
    context "when application form exists" do
      before do
        stub_const("TestApplicationForm", Class.new)
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?)
        generator.invoke_all
      end

      it "does not prompt user" do
        expect(generator).not_to have_received(:yes?)
      end

      it "does not generate application form" do
        expect(generator).not_to have_received(:generate).with("strata:application_form", anything)
      end
    end

    context "when application form does not exist and user declines" do
      before do
        hide_const("TestApplicationForm")
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?).and_return(false)
        generator.invoke_all
      end

      it "prompts user once" do
        expect(generator).to have_received(:yes?).exactly(1).times
      end

      it "does not generate application form" do
        expect(generator).not_to have_received(:generate).with("strata:application_form", anything)
      end
    end

    context "when application form does not exist and user agrees" do
      before do
        hide_const("TestApplicationForm")
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?).and_return(true)
        generator.invoke_all
      end

      it "prompts user once" do
        expect(generator).to have_received(:yes?).exactly(1).times
      end

      it "generates application form" do
        expect(generator).to have_received(:generate).with("strata:application_form", "Test").exactly(1).times
      end
    end

    context "when TestApplicationForm does not exist and skip-application-form option is provided" do
      let(:options) { { case: case_option, "application-form": app_form_option, "skip-application-form": true } }

      before do
        hide_const("TestApplicationForm")
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?)
        generator.invoke_all
      end

      it "does not prompt user" do
        expect(generator).not_to have_received(:yes?)
      end

      it "does not generate application form" do
        expect(generator).not_to have_received(:generate).with("strata:application_form", anything)
      end
    end

    describe "with force-application-form option" do
      let(:options) { { case: case_option, "application-form": app_form_option, "force-application-form": true } }

      before do
        hide_const("TestApplicationForm")
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?)
        generator.invoke_all
      end

      it "does not prompt user" do
        expect(generator).not_to have_received(:yes?)
      end

      it "generates application form" do
        expect(generator).to have_received(:generate).with("strata:application_form", "Test").exactly(1).times
      end
    end

    describe "when application form name does not end with ApplicationForm" do
      let(:options) { { case: case_option, "application-form": "CustomForm", "force-application-form": true } }

      before do
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?)
        generator.invoke_all
      end

      it "uses the full name as base name" do
        expect(generator).to have_received(:generate).with("strata:application_form", "CustomForm").exactly(1).times
      end
    end

    describe "when application form is namespaced" do
      let(:options) { { case: case_option, "application-form": "MyModule::TestApplicationForm", "force-application-form": true } }

      before do
        allow(generator).to receive(:generate)
        allow(generator).to receive(:yes?)
        generator.invoke_all
      end

      it "correctly extracts base name from namespaced class" do
        expect(generator).to have_received(:generate).with("strata:application_form", "MyModule::Test").exactly(1).times
      end
    end
  end
end
