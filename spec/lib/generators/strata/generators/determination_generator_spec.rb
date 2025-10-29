# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/determination/determination_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::DeterminationGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([], options.merge(quiet: true), destination_root: destination_root) }
  let(:options) { {} }

  before do
    FileUtils.mkdir_p("#{destination_root}/db/migrate")
    FileUtils.mkdir_p("#{destination_root}/app/models/concerns")
    FileUtils.mkdir_p("#{destination_root}/spec/models")
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe 'file creation' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_determinations).and_return(true)
      generator.invoke_all
    end

    it 'creates a migration file' do
      migration_file = Dir.glob("#{destination_root}/db/migrate/*_create_strata_determinations.rb").first
      expect(migration_file).to be_present
    end

    it 'creates a Determination model file' do
      model_file = "#{destination_root}/app/models/determination.rb"
      expect(File.exist?(model_file)).to be true
    end

    it 'creates a Determinable concern file' do
      concern_file = "#{destination_root}/app/models/concerns/determinable.rb"
      expect(File.exist?(concern_file)).to be true
    end

    it 'creates a Determination spec file' do
      spec_file = "#{destination_root}/spec/models/determination_spec.rb"
      expect(File.exist?(spec_file)).to be true
    end

    it 'creates a Determinable spec file' do
      concern_spec_file = "#{destination_root}/spec/models/concerns/determinable_spec.rb"
      expect(File.exist?(concern_spec_file)).to be true
    end
  end

  describe 'migration content' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_determinations).and_return(true)
      generator.invoke_all
    end

    it 'creates strata_determinations table with UUID primary key' do
      migration_file = Dir.glob("#{destination_root}/db/migrate/*_create_strata_determinations.rb").first
      content = File.read(migration_file)

      expect(content).to include('create_table :strata_determinations, id: :uuid')
    end
  end

  describe 'model content' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_determinations).and_return(true)
      generator.invoke_all
    end

    it 'creates Determination class inheriting from Strata::Determination' do
      model_file = "#{destination_root}/app/models/determination.rb"
      content = File.read(model_file)

      expect(content).to include('class Determination < Strata::Determination')
    end
  end

  describe 'concern content' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_determinations).and_return(true)
      generator.invoke_all
    end

    it 'creates Determinable module including Strata::Determinable' do
      concern_file = "#{destination_root}/app/models/concerns/determinable.rb"
      content = File.read(concern_file)

      expect(content).to include('module Determinable')
      expect(content).to include('include Strata::Determinable')
    end
  end

  describe 'spec content' do
    before do
      allow(ActiveRecord::Base.connection).to receive(:table_exists?).with(:strata_determinations).and_return(true)
      generator.invoke_all
    end

    it 'creates spec file with inheritance test' do
      spec_file = "#{destination_root}/spec/models/determination_spec.rb"
      content = File.read(spec_file)

      expect(content).to include('RSpec.describe Determination')
    end

    it 'creates determinable spec file with pending examples' do
      concern_spec_file = "#{destination_root}/spec/models/concerns/determinable_spec.rb"
      content = File.read(concern_spec_file)

      expect(content).to include('RSpec.describe Determinable')
    end
  end
end
