# frozen_string_literal: true

require 'rails_helper'
require 'generators/strata/migration/migration_generator'
require 'fileutils'
require 'tmpdir'

RSpec.describe Strata::Generators::MigrationGenerator, type: :generator do
  let(:destination_root) { Dir.mktmpdir }
  let(:generator) { described_class.new([ name, *attrs ], options.merge(quiet: true), destination_root: destination_root) }
  let(:name) { 'CreateTestRecords' }
  let(:attrs) { [] }
  let(:options) { {} }

  before do
    FileUtils.mkdir_p("#{destination_root}/db/migrate")
    allow(generator).to receive(:generate)
  end

  after do
    FileUtils.rm_rf(destination_root)
  end

  describe "attribute handling" do
    context "with built-in Rails types" do
      let(:attrs) { [ "name:string", "age:integer", "active:boolean" ] }

      it "passes through built-in types directly" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "name:string",
          "age:integer",
          "active:boolean"
        )
      end
    end

    context "with Strata attribute types" do
      let(:attrs) { [ "full_name:name", "home_address:address" ] }

      it "maps Strata types to their corresponding database columns" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "full_name_first:string",
          "full_name_middle:string",
          "full_name_last:string",
          "full_name_suffix:string",
          "home_address_street_line_1:string",
          "home_address_street_line_2:string",
          "home_address_city:string",
          "home_address_state:string",
          "home_address_zip_code:string"
        )
      end
    end

    context "with mixed attribute types" do
      let(:attrs) { [ "full_name:name", "email:string", "birth_date:us_date" ] }

      it "handles both Strata and built-in types correctly" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "full_name_first:string",
          "full_name_middle:string",
          "full_name_last:string",
          "full_name_suffix:string",
          "email:string",
          "birth_date:date"
        )
      end
    end

    context "with array option" do
      let(:attrs) { [ "tags:string:array", "categories:text:array" ] }

      it "creates jsonb columns for array attributes" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "tags:jsonb",
          "categories:jsonb"
        )
      end
    end

    context "with range option" do
      let(:attrs) { [ "period:us_date:range", "amount:money:range" ] }

      it "creates start and end columns for range attributes" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "period_start:date",
          "period_end:date",
          "amount_start:integer",
          "amount_end:integer"
        )
      end
    end

    context "with memorable_date type" do
      let(:attrs) { [ "reminder_date:memorable_date" ] }

      it "maps to date column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "reminder_date:date"
        )
      end
    end

    context "with money type" do
      let(:attrs) { [ "amount:money" ] }

      it "maps to integer column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "amount:integer"
        )
      end
    end

    context "with tax_id type" do
      let(:attrs) { [ "ssn:tax_id" ] }

      it "maps to string column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "ssn:string"
        )
      end
    end

    context "with us_date type" do
      let(:attrs) { [ "due_date:us_date" ] }

      it "maps to date column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "due_date:date"
        )
      end
    end

    context "with year_month type" do
      let(:attrs) { [ "reporting_period:year_month" ] }

      it "creates string column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "reporting_period:string"
        )
      end
    end

    context "with year_quarter type" do
      let(:attrs) { [ "fiscal_period:year_quarter" ] }

      it "creates string column" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "fiscal_period:string"
        )
      end
    end

    context "with user_facing_id type" do
      let(:attrs) { [ "user_facing_id:user_facing_id" ] }

      it "creates a bigserial sequence column with a unique index" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "user_facing_id_sequence:bigint!:uniq"
        )
      end
    end

    context "with a custom-named user_facing_id" do
      let(:attrs) { [ "claim_id:user_facing_id" ] }

      it "appends _sequence to the attribute name" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "claim_id_sequence:bigint!:uniq"
        )
      end
    end

    context "with user_facing_id mixed alongside other attributes" do
      let(:attrs) { [ "full_name:name", "user_facing_id:user_facing_id", "email:string" ] }

      it "emits the sequence column inline with the others" do
        generator.create_migration_file
        expect(generator).to have_received(:generate).with(
          "migration",
          "CreateTestRecords",
          "full_name_first:string",
          "full_name_middle:string",
          "full_name_last:string",
          "full_name_suffix:string",
          "user_facing_id_sequence:bigint!:uniq",
          "email:string"
        )
      end
    end

    context "when user_facing_id is combined with :array" do
      let(:attrs) { [ "user_facing_id:user_facing_id:array" ] }

      it "raises an informative error" do
        expect { generator.create_migration_file }.to raise_error(
          ArgumentError, /user_facing_id.*does not support.*array/i
        )
      end
    end

    context "when user_facing_id is combined with :range" do
      let(:attrs) { [ "user_facing_id:user_facing_id:range" ] }

      it "raises an informative error" do
        expect { generator.create_migration_file }.to raise_error(
          ArgumentError, /user_facing_id.*does not support.*range/i
        )
      end
    end
  end

  describe "rewriting :bigint to :bigserial for user_facing_id sequence columns" do
    # The migration generator emits `:bigint!` to Rails' migration generator
    # (Rails rejects `:bigserial` since it's not in PostgreSQL's
    # native_database_types map) and then patches the generated file to
    # restore the autoincrementing sequence semantics. These specs stub
    # `generate` to write a fixture migration in the format Rails would
    # produce, then assert the rewrite runs.
    let(:migration_filename) { "20260101000000_#{name.underscore}.rb" }
    let(:migration_path) { File.join(destination_root, "db/migrate", migration_filename) }

    context "when Rails emits the create_table form (t.bigint :col)" do
      let(:attrs) { [ "user_facing_id:user_facing_id" ] }

      before do
        allow(generator).to receive(:generate) do
          File.write(migration_path, <<~RUBY)
            class CreateTestRecords < ActiveRecord::Migration[8.0]
              def change
                create_table :test_records do |t|
                  t.bigint :user_facing_id_sequence, null: false

                  t.timestamps
                end
                add_index :test_records, :user_facing_id_sequence, unique: true
              end
            end
          RUBY
        end
      end

      it "rewrites :bigint to :bigserial for the sequence column" do
        generator.create_migration_file
        contents = File.read(migration_path)
        expect(contents).to include("t.bigserial :user_facing_id_sequence, null: false")
        expect(contents).not_to include("t.bigint :user_facing_id_sequence")
      end
    end

    context "when Rails emits the add_column form (..., :col, :bigint, ...)" do
      let(:name) { "AddUserFacingIdToTestRecords" }
      let(:attrs) { [ "user_facing_id:user_facing_id" ] }

      before do
        allow(generator).to receive(:generate) do
          File.write(migration_path, <<~RUBY)
            class AddUserFacingIdToTestRecords < ActiveRecord::Migration[8.0]
              def change
                add_column :test_records, :user_facing_id_sequence, :bigint, null: false
                add_index :test_records, :user_facing_id_sequence, unique: true
              end
            end
          RUBY
        end
      end

      it "rewrites :bigint to :bigserial for the sequence column" do
        generator.create_migration_file
        contents = File.read(migration_path)
        expect(contents).to include(":user_facing_id_sequence, :bigserial, null: false")
        expect(contents).not_to include(":user_facing_id_sequence, :bigint")
      end
    end

    context "with a non-user_facing_id bigint column in the same migration" do
      let(:attrs) { [ "user_facing_id:user_facing_id", "count:bigint" ] }

      before do
        allow(generator).to receive(:generate) do
          File.write(migration_path, <<~RUBY)
            class CreateTestRecords < ActiveRecord::Migration[8.0]
              def change
                create_table :test_records do |t|
                  t.bigint :user_facing_id_sequence, null: false
                  t.bigint :count
                end
                add_index :test_records, :user_facing_id_sequence, unique: true
              end
            end
          RUBY
        end
      end

      it "rewrites only the sequence column and leaves other bigint columns alone" do
        generator.create_migration_file
        contents = File.read(migration_path)
        expect(contents).to include("t.bigserial :user_facing_id_sequence, null: false")
        expect(contents).to include("t.bigint :count")
      end
    end

    context "with multiple user_facing_id attributes" do
      let(:attrs) { [ "user_facing_id:user_facing_id", "claim_id:user_facing_id" ] }

      before do
        allow(generator).to receive(:generate) do
          File.write(migration_path, <<~RUBY)
            class CreateTestRecords < ActiveRecord::Migration[8.0]
              def change
                create_table :test_records do |t|
                  t.bigint :user_facing_id_sequence, null: false
                  t.bigint :claim_id_sequence, null: false
                end
                add_index :test_records, :user_facing_id_sequence, unique: true
                add_index :test_records, :claim_id_sequence, unique: true
              end
            end
          RUBY
        end
      end

      it "rewrites each sequence column independently" do
        generator.create_migration_file
        contents = File.read(migration_path)
        expect(contents).to include("t.bigserial :user_facing_id_sequence, null: false")
        expect(contents).to include("t.bigserial :claim_id_sequence, null: false")
        expect(contents).not_to include("t.bigint")
      end
    end

    context "when no migration file matches the expected name" do
      let(:attrs) { [ "user_facing_id:user_facing_id" ] }

      it "does not raise" do
        # `generate` is stubbed to do nothing, so no file is written
        expect { generator.create_migration_file }.not_to raise_error
      end
    end
  end

  describe "complex scenarios" do
    let(:attrs) { [
      "person_name:name",
      "contact_address:address",
      "tags:array",
      "valid_period:us_date:range",
      "amounts:money:array",
      "fiscal_quarter:year_quarter",
      "reporting_period:year_month"
    ]}

    it "handles complex combinations of types and options correctly" do
      generator.create_migration_file
      expect(generator).to have_received(:generate).with(
        "migration",
        "CreateTestRecords",
        "person_name_first:string",
        "person_name_middle:string",
        "person_name_last:string",
        "person_name_suffix:string",
        "contact_address_street_line_1:string",
        "contact_address_street_line_2:string",
        "contact_address_city:string",
        "contact_address_state:string",
        "contact_address_zip_code:string",
        "tags:jsonb",
        "valid_period_start:date",
        "valid_period_end:date",
        "amounts:jsonb",
        "fiscal_quarter:string",
        "reporting_period:string"
      )
    end
  end
end
