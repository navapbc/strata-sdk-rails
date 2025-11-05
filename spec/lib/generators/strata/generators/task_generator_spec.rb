# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/task/task_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::TaskGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([ task_name ], options.merge(quiet: true), destination_root: destination_root) }
  let(:task_name) { 'TestTask' }
  let(:options) { {} }

  before do
    FileUtils.mkdir_p("#{destination_root}/app/models")
    FileUtils.mkdir_p("#{destination_root}/spec/models")
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "with basic name only" do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(true)
      generator.invoke_all
    end

    it "creates task file with correct naming" do
      task_file = "#{destination_root}/app/models/test_task.rb"
      expect(File.exist?(task_file)).to be true

      content = File.read(task_file)
      expect(content).to include("class TestTask < Strata::Task")
    end

    it "creates test file" do
      test_file = "#{destination_root}/spec/models/test_task_spec.rb"
      expect(File.exist?(test_file)).to be true

      content = File.read(test_file)
      expect(content).to include("RSpec.describe TestTask")
      expect(content).to include("expect(described_class.superclass).to eq(Strata::Task)")
    end
  end

  describe "with custom parent option" do
    let(:options) { { parent: 'CustomTask' } }

    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(true)
      generator.invoke_all
    end

    it "uses custom parent class" do
      task_file = "#{destination_root}/app/models/test_task.rb"
      content = File.read(task_file)
      expect(content).to include("class TestTask < CustomTask")
    end
  end

  describe "name formatting" do
    [
      [ 'Review', 'ReviewTask' ],
      [ 'ReviewTask', 'ReviewTask' ],
      [ 'review_application', 'ReviewApplicationTask' ],
      [ 'PROCESS_PAYMENT', 'ProcessPaymentTask' ]
    ].each do |input, expected|
      context "when name is '#{input}'" do
        let(:task_name) { input }

        before do
          allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(true)
          generator.invoke_all
        end

        it "formats to '#{expected}'" do
          task_file = "#{destination_root}/app/models/#{expected.underscore}.rb"
          expect(File.exist?(task_file)).to be true

          content = File.read(task_file)
          expect(content).to include("class #{expected} < Strata::Task")
        end
      end
    end
  end

  describe "database table check" do
    context "when strata_tasks table exists" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(true)
      end

      it "does not prompt for migration" do
        allow(generator).to receive(:yes?)
        generator.invoke_all
        expect(generator).not_to have_received(:yes?)
      end
    end

    context "when strata_tasks table does not exist" do
      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(false)
        allow(generator).to receive(:say)
        allow(generator).to receive(:yes?).and_return(false)
      end

      it "warns about missing table" do
        allow(generator).to receive(:say)
        generator.invoke_all
        expect(generator).to have_received(:say).with("Warning: strata_tasks table does not exist.", :yellow)
      end

      it "prompts to create and run migrations" do
        generator.invoke_all
        expect(generator).to have_received(:yes?).with("Would you like to create and run the strata_tasks migration now? (y/n)")
      end

      it "creates migration and runs db:migrate when user agrees" do
        FileUtils.mkdir_p("#{destination_root}/db/migrate")
        allow(generator).to receive(:yes?).and_return(true)
        allow(generator).to receive(:rails_command)
        generator.invoke_all
        expect(generator).to have_received(:rails_command).with("db:migrate")

        # Check that migration file was created
        migration_files = Dir.glob("#{destination_root}/db/migrate/*_create_strata_tasks.rb")
        expect(migration_files.length).to eq(1)
      end
    end

    context "with skip-migration-check option" do
      let(:options) { { "skip-migration-check": true } }

      before do
        allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_tasks).and_return(false)
      end

      it "skips database check" do
        allow(generator).to receive(:say)
        allow(generator).to receive(:yes?)
        generator.invoke_all
        expect(generator).not_to have_received(:say)
        expect(generator).not_to have_received(:yes?)
      end
    end
  end
end
