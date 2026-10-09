# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::QuestionPage do
  before do
    test_model_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :first_name, :string
      validates :first_name, presence: true, on: :first_name
    end

    stub_const("TestModel", test_model_class)
  end

  let(:record) { TestModel.new }

  describe "with only required attributes" do
    let(:page) { described_class.new("first_name") }

    it "uses the provided name as the set of fields" do
      expect(page.name).to eq("first_name")
      expect(page.fields).to eq([ :first_name ])
    end

    it "is always needed" do
      expect(page).to be_needed(record)
    end

    it "is completed based on the page name" do
      expect(page).not_to be_completed(record)

      record.first_name = "Mary"
      expect(page).to be_completed(record)
    end

    it "returns the correct pathnames" do
      expect(page.edit_pathname).to eq("edit_first_name")
      expect(page.update_pathname).to eq("update_first_name")
    end

    it "is not in a loop" do
      expect(page).not_to be_in_loop
    end
  end

  describe "with an enclosing loop" do
    let(:loop_node) { Strata::Flows::Loop.new(:prior_employer, association: :sample_employment_details) }
    let(:page) { described_class.new("business_name", loop: loop_node) }

    it "is marked as in a loop" do
      expect(page).to be_in_loop
      expect(page.loop).to eq(loop_node)
    end

    it "namespaces edit_pathname and update_pathname by the loop name" do
      expect(page.edit_pathname).to eq("edit_prior_employer_business_name")
      expect(page.update_pathname).to eq("update_prior_employer_business_name")
    end

    context "with stubbed parent and child classes" do
      before do
        parent_class = Class.new { def self.name = "SampleApplicationForm" }
        child_class = Class.new { def self.name = "SampleEmploymentDetail" }
        stub_const("SampleApplicationForm", parent_class)
        stub_const("SampleEmploymentDetail", child_class)
      end

      let(:flow_record) { SampleApplicationForm.new }
      let(:child_record) { SampleEmploymentDetail.new }

      it "uses the nested route helper for edit_path, passing parent and child" do
        allow(page).to receive(:edit_prior_employer_business_name_sample_application_form_sample_employment_detail_path)
          .and_return("/sample_application_forms/1/sample_employment_details/2/edit_prior_employer_business_name")

        expect(page.edit_path(flow_record, child_record))
          .to eq("/sample_application_forms/1/sample_employment_details/2/edit_prior_employer_business_name")
        expect(page).to have_received(:edit_prior_employer_business_name_sample_application_form_sample_employment_detail_path)
          .with(flow_record, child_record)
      end

      it "uses the nested route helper for update_path, passing parent and child" do
        allow(page).to receive(:update_prior_employer_business_name_sample_application_form_sample_employment_detail_path)
          .and_return("/sample_application_forms/1/sample_employment_details/2/update_prior_employer_business_name")

        expect(page.update_path(flow_record, child_record))
          .to eq("/sample_application_forms/1/sample_employment_details/2/update_prior_employer_business_name")
        expect(page).to have_received(:update_prior_employer_business_name_sample_application_form_sample_employment_detail_path)
          .with(flow_record, child_record)
      end

      it "builds the helper name from the singularized association name (not the child class name)" do
        # Capture the symbol passed to `send` to verify we route through association.singularize.
        captured_method = nil
        allow(page).to receive(:send).and_wrap_original do |original, method_name, *args|
          captured_method = method_name
          "/stubbed"
        end

        page.edit_path(flow_record, child_record)

        expect(captured_method.to_s).to eq("edit_prior_employer_business_name_sample_application_form_sample_employment_detail_path")
      end
    end

    it "evaluates needed?/completed? against the loop record, not the flow record" do
      child_class = Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes
        attribute :business_name, :string
        validates :business_name, presence: true, on: :business_name
      end
      stub_const("PriorEmployer", child_class)

      child_record = PriorEmployer.new
      expect(page).not_to be_completed(child_record)

      child_record.business_name = "Acme"
      expect(page).to be_completed(child_record)
    end

    describe "with conditional if" do
      let(:page) do
        described_class.new("role", loop: loop_node, if: ->(loop_record) { loop_record.business_name.present? })
      end

      it "evaluates the predicate against the loop record" do
        child_class = Class.new do
          include ActiveModel::Model
          include ActiveModel::Attributes
          attribute :business_name, :string
        end
        stub_const("PriorEmployer", child_class)

        empty_child = PriorEmployer.new
        filled_child = PriorEmployer.new(business_name: "Acme")

        expect(page).not_to be_needed(empty_child)
        expect(page).to be_needed(filled_child)
      end
    end
  end

  describe "with conditional if" do
    let(:page) { described_class.new("first_name", if: ->(record) { record.first_name.nil? }) }

    it "is needed if conditional is true" do
      expect(page).to be_needed(record)
    end

    it "skips the page if conditional is false" do
      record.first_name = "Minnie"
      expect(page).not_to be_needed(record)
    end
  end

  describe "with explicit fields" do
    let(:page) { described_class.new("name", fields: [ :first_name, :last_name ]) }

    it "uses the passed in fields" do
      expect(page.fields).to eq([ :first_name, :last_name ])
    end
  end

  describe "#attributes" do
    before do
      test_model_class = Class.new(ActiveRecord::Base) do
        self.table_name = "test_records"
        include Strata::Attributes

        strata_attribute :applicant_name, :name
        strata_attribute :home_address, :address
        strata_attribute :date_of_birth, :memorable_date
        strata_attribute :weekly_wage, :money
        strata_attribute :tax_id, :tax_id
        strata_attribute :adopted_on, :us_date
        strata_attribute :period, :us_date, range: true
      end

      stub_const("StrataTestModel", test_model_class)
    end

    let(:record) { StrataTestModel.new }

    it "expands name fields into component columns" do
      page = described_class.new("name", fields: [ :applicant_name ])
      expect(page.attributes(record.class)).to eq([
        :applicant_name_first, :applicant_name_middle, :applicant_name_last, :applicant_name_suffix
      ])
    end

    it "expands address fields into component columns" do
      page = described_class.new("address", fields: [ :home_address ])
      expect(page.attributes(record.class)).to eq([
        :home_address_street_line_1, :home_address_street_line_2,
        :home_address_city, :home_address_state, :home_address_zip_code
      ])
    end

    it "expands memorable_date fields into a multi-parameter hash" do
      page = described_class.new("dob", fields: [ :date_of_birth ])
      expect(page.attributes(record.class)).to eq([
        { date_of_birth: [ :month, :day, :year ] }
      ])
    end

    it "expands range fields into start and end columns" do
      page = described_class.new("period", fields: [ :period ])
      expect(page.attributes(record.class)).to eq([
        :period_start, :period_end
      ])
    end

    it "passes through single-column strata fields unchanged" do
      page = described_class.new("wage", fields: [ :weekly_wage ])
      expect(page.attributes(record.class)).to eq([ :weekly_wage ])
    end

    it "passes through non-strata fields unchanged" do
      page = described_class.new("misc", fields: [ :some_plain_field ])
      expect(page.attributes(record.class)).to eq([ :some_plain_field ])
    end

    it "handles a mix of strata and non-strata fields" do
      page = described_class.new("mixed", fields: [ :applicant_name, :tax_id, :date_of_birth ])
      expect(page.attributes(record.class)).to eq([
        :applicant_name_first, :applicant_name_middle, :applicant_name_last, :applicant_name_suffix,
        :tax_id,
        { date_of_birth: [ :month, :day, :year ] }
      ])
    end
  end
end
