# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/events/events_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::EventsGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], { quiet: true }, destination_root: destination_root) }
  let(:generated_migration) { Dir.glob("#{destination_root}/db/migrate/*_create_strata_events.rb").first }

  before do
    FileUtils.mkdir_p("#{destination_root}/db/migrate")
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe 'migration' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_events).and_return(true)
      generator.invoke_all
    end

    it 'copies the events migration into the host application' do
      expect(generated_migration).to be_present
    end

    it "matches the dummy app's migration, so hosts get the tables the engine's models expect" do
      dummy_migration = Dir.glob(Rails.root.join('db/migrate/*_create_strata_events.rb')).first

      expect(File.read(generated_migration)).to eq(File.read(dummy_migration))
    end
  end

  describe 'table existence check' do
    it 'warns when the table does not exist and the user declines to migrate' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_events).and_return(false)
      allow(generator).to receive(:yes?).and_return(false)
      allow(generator).to receive(:say)

      generator.invoke_all

      expect(generator).to have_received(:say).with(/strata_events table does not exist/, :yellow)
    end

    it 'skips the table check when --skip-migration-check is set' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)

      described_class.new([], { 'skip-migration-check': true, quiet: true }, destination_root: destination_root)
        .invoke_all

      expect(ActiveRecord::Base.connection).not_to have_received(:table_exists?).with(:strata_events)
    end
  end
end
