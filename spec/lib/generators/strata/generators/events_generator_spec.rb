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
      dummy_migration = Dir.glob(Rails.root.join('db/migrate/*_create_strata_events.rb')).sole

      expect(File.read(generated_migration)).to eq(File.read(dummy_migration))
    end
  end

  describe 'running the generator again' do
    include ActiveSupport::Testing::TimeHelpers

    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_events).and_return(true)
    end

    def migrations
      Dir.glob("#{destination_root}/db/migrate/*_create_strata_events.rb")
    end

    def run_generator(options = {})
      described_class.new([], { quiet: true }.merge(options), destination_root: destination_root).invoke_all
    end

    it 'does not create a second migration when the events migration is already installed' do
      travel_to(Time.utc(2026, 10, 16, 12, 0, 0)) { run_generator }
      travel_to(Time.utc(2026, 10, 17, 12, 0, 0)) { run_generator }

      expect(migrations.size).to eq(1)
    end

    it 'keeps the originally installed migration' do
      travel_to(Time.utc(2026, 10, 16, 12, 0, 0)) { run_generator }
      original = migrations.first
      travel_to(Time.utc(2026, 10, 17, 12, 0, 0)) { run_generator }

      expect(migrations).to eq([ original ])
    end

    it 'refuses to overwrite an installed migration the host has changed' do
      File.write("#{destination_root}/db/migrate/20260101000000_create_strata_events.rb", "# edited by host\n")

      expect { run_generator }.to raise_error(Rails::Generators::Error, /already named create_strata_events/)
    end

    it 'leaves a changed migration in place with --skip' do
      changed = "#{destination_root}/db/migrate/20260101000000_create_strata_events.rb"
      File.write(changed, "# edited by host\n")

      run_generator(skip: true)

      expect(migrations).to eq([ changed ])
      expect(File.read(changed)).to eq("# edited by host\n")
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

    it 'runs db:migrate when the table does not exist and the user agrees' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_events).and_return(false)
      allow(generator).to receive(:yes?).and_return(true)
      allow(generator).to receive(:rails_command)

      generator.invoke_all

      expect(generator).to have_received(:rails_command).with('db:migrate')
    end

    [ ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished ].each do |error|
      context "when the database is not reachable (#{error.name.demodulize})" do
        before do
          allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_events).and_raise(error)
          allow(generator).to receive(:yes?)
          allow(generator).to receive(:say)
        end

        it 'still installs the migration' do
          generator.invoke_all

          expect(generated_migration).to be_present
        end

        it 'warns that the database must be created and migrated, without offering to migrate' do
          generator.invoke_all

          expect(generator).to have_received(:say).with(/could not connect to the database.*db:create.*db:migrate/i, :yellow)
          expect(generator).not_to have_received(:yes?)
        end
      end
    end

    it 'skips the table check when --skip-migration-check is set' do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?)

      described_class.new([], { 'skip-migration-check': true, quiet: true }, destination_root: destination_root)
        .invoke_all

      expect(ActiveRecord::Base.connection).not_to have_received(:table_exists?).with(:strata_events)
    end
  end
end
