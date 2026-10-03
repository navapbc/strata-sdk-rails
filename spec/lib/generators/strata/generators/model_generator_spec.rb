# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/model/model_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::ModelGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new(args, options.merge(quiet: true), destination_root: destination_root) }
  let(:args) { [ name ] }
  let(:options) { {} }
  let(:name) { 'TestModel' }

  before do
    FileUtils.mkdir_p("#{destination_root}/app/models")
    FileUtils.mkdir_p("#{destination_root}/db/migrate")
    allow(generator).to receive(:generate)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "generating a model with Strata attributes" do
    let(:args) { [ "Dog", "name:name", "owner:name", "age:integer" ] }

    context "with default options" do
      it "calls strata:migration generator for all attributes" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with("strata:migration", "CreateDogs", "name:name", "owner:name", "age:integer")
      end

      it "does not call active_record:migration generator" do
        generator.create_migration_file
        expect(generator).not_to have_received(:generate).with("active_record:migration", anything, anything)
      end
    end

    it "creates model file with Strata::Attributes" do
      allow(generator).to receive(:generate).and_call_original
      allow(File).to receive(:join).and_call_original
      allow(generator).to receive(:template)

      generator.create_model_file
      expect(generator).to have_received(:template).with("model.rb.tt", "app/models/dog.rb")
    end
  end

  describe "generating a model with only regular Rails attributes" do
    let(:args) { [ "Cat", "name:string", "age:integer" ] }

    context "with default options" do
      it "calls strata:migration generator for all attributes" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with("strata:migration", "CreateCats", "name:string", "age:integer")
      end

      it "does not call active_record:migration generator" do
        generator.create_migration_file
        expect(generator).not_to have_received(:generate).with("active_record:migration", anything, anything)
      end
    end
  end

  describe "generating a model with mixed attributes" do
    let(:args) { [ "Person", "full_name:name", "email:string", "birth_date:date" ] }

    context "with default options" do
      it "calls strata:migration generator for all attributes" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with("strata:migration", "CreatePeople", "full_name:name", "email:string", "birth_date:date")
      end

      it "does not call active_record:migration generator" do
        generator.create_migration_file
        expect(generator).not_to have_received(:generate).with("active_record:migration", anything, anything)
      end
    end
  end

  describe "attribute parsing" do
    let(:args) { [ "Test", "name:name", "count:integer", "email:string" ] }

    it "handles all attributes correctly" do
      generator.create_migration_file
      expect(generator).to have_received(:generate).with("strata:migration", "CreateTests", "name:name", "count:integer", "email:string")
    end
  end

  describe "generating a model with a user_facing_id attribute" do
    let(:args) { [ "Claim", "claim_id:user_facing_id" ] }

    before do
      allow(SecureRandom).to receive(:random_number).with(0xFFFF_FFFF).and_return(0xdeadbeee)
    end

    it "passes the attribute through to strata:migration unchanged" do
      generator.create_migration_file
      expect(generator).to have_received(:generate).with(
        "strata:migration", "CreateClaims", "claim_id:user_facing_id"
      )
    end

    it "renders strata_attribute with prefix TODO, a fresh random key, and a TODO comment" do
      generator.create_model_file
      contents = File.read("#{destination_root}/app/models/claim.rb")
      expect(contents).to include("include Strata::Attributes")
      expect(contents).to match(
        /# TODO: replace prefix "TODO".*\n  strata_attribute :claim_id, :user_facing_id, prefix: "TODO", key: 0xdeadbeef/
      )
    end

    it "does not fall through to the plain Rails attribute branch" do
      generator.create_model_file
      contents = File.read("#{destination_root}/app/models/claim.rb")
      expect(contents).not_to match(/^\s*attribute :claim_id, :user_facing_id/)
    end
  end

  describe "generating a model with multiple user_facing_id attributes" do
    let(:args) { [ "Case", "user_facing_id:user_facing_id", "claim_user_facing_id:user_facing_id" ] }

    before do
      allow(SecureRandom).to receive(:random_number).with(0xFFFF_FFFF)
        .and_return(0xaaaaaaa9, 0xbbbbbbba)
    end

    it "gives each attribute its own freshly generated key" do
      generator.create_model_file
      contents = File.read("#{destination_root}/app/models/case.rb")
      expect(contents).to include('strata_attribute :user_facing_id, :user_facing_id, prefix: "TODO", key: 0xaaaaaaaa')
      expect(contents).to include('strata_attribute :claim_user_facing_id, :user_facing_id, prefix: "TODO", key: 0xbbbbbbbb')
    end
  end

  describe "generating a model with user_facing_id mixed with other Strata and Rails attributes" do
    let(:args) { [ "Claim", "full_name:name", "claim_id:user_facing_id", "email:string" ] }

    before do
      allow(SecureRandom).to receive(:random_number).with(0xFFFF_FFFF).and_return(0x12345677)
    end

    it "renders each attribute in its appropriate form" do
      generator.create_model_file
      contents = File.read("#{destination_root}/app/models/claim.rb")
      expect(contents).to include("strata_attribute :full_name, :name")
      expect(contents).to include('strata_attribute :claim_id, :user_facing_id, prefix: "TODO", key: 0x12345678')
      expect(contents).to include("attribute :email, :string")
    end

    it "still passes everything to strata:migration verbatim" do
      generator.create_migration_file
      expect(generator).to have_received(:generate).with(
        "strata:migration", "CreateClaims",
        "full_name:name", "claim_id:user_facing_id", "email:string"
      )
    end
  end

  describe "when model file already exists" do
    let(:args) { [ "TestModel" ] }

    before do
      File.write("#{destination_root}/app/models/test_model.rb", "# existing file")
      allow(generator).to receive(:generate).and_call_original
    end

    it "raises an error" do
      expect {
        generator.create_model_file
      }.to raise_error(Thor::Error, /Model file already exists/)
    end
  end
end
