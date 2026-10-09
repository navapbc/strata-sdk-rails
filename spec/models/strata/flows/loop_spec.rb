# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::Loop do
  before do
    child_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :business_name, :string
      attribute :role, :string
      validates :business_name, presence: true, on: :business_name
      validates :role, presence: true, on: :role
    end

    parent_class = Class.new do
      include ActiveModel::Model
      attr_accessor :prior_employers

      def initialize(prior_employers: [])
        @prior_employers = prior_employers
      end
    end

    stub_const("PriorEmployer", child_class)
    stub_const("EmploymentForm", parent_class)
  end

  let(:business_name_page) { Strata::Flows::QuestionPage.new(:business_name) }
  let(:role_page) { Strata::Flows::QuestionPage.new(:role) }

  describe "#initialize" do
    it "stores name, association, and pages" do
      loop_node = described_class.new(:prior_employer, association: :prior_employers)

      expect(loop_node.name).to eq(:prior_employer)
      expect(loop_node.association).to eq(:prior_employers)
      expect(loop_node.pages).to eq([])
      expect(loop_node.scope).to be_nil
    end

    it "defaults association to the loop name when not provided" do
      loop_node = described_class.new(:prior_employers)

      expect(loop_node.name).to eq(:prior_employers)
      expect(loop_node.association).to eq(:prior_employers)
    end

    it "stores the scope when provided" do
      scope = ->(rel) { rel }
      loop_node = described_class.new(:prior_employers, scope: scope)

      expect(loop_node.scope).to eq(scope)
    end
  end

  describe "#records_for" do
    let(:child_a) { PriorEmployer.new(business_name: "Acme") }
    let(:child_b) { PriorEmployer.new(business_name: "Globex") }

    it "returns the association on the flow record" do
      flow_record = EmploymentForm.new(prior_employers: [ child_a, child_b ])

      loop_node = described_class.new(:prior_employer, association: :prior_employers)

      expect(loop_node.records_for(flow_record)).to eq([ child_a, child_b ])
    end

    context "with a Symbol scope" do
      before do
        scoped_relation_class = Class.new do
          def initialize(records)
            @records = records
          end

          def active
            @records.select { |r| r.business_name == "Globex" }
          end
        end

        stub_const("ScopedRelation", scoped_relation_class)
      end

      it "applies the named scope on the relation" do
        flow_record = EmploymentForm.new(prior_employers: ScopedRelation.new([ child_a, child_b ]))

        loop_node = described_class.new(:prior_employer, association: :prior_employers, scope: :active)

        expect(loop_node.records_for(flow_record)).to eq([ child_b ])
      end
    end

    context "with a Proc scope" do
      it "calls the proc with the relation and returns its result" do
        flow_record = EmploymentForm.new(prior_employers: [ child_a, child_b ])

        loop_node = described_class.new(
          :prior_employer,
          association: :prior_employers,
          scope: ->(records) { records.select { |r| r.business_name.start_with?("A") } }
        )

        expect(loop_node.records_for(flow_record)).to eq([ child_a ])
      end
    end

    context "with an invalid scope type" do
      it "raises ArgumentError" do
        flow_record = EmploymentForm.new(prior_employers: [ child_a ])

        loop_node = described_class.new(:prior_employer, association: :prior_employers, scope: "active")

        expect { loop_node.records_for(flow_record) }.to raise_error(ArgumentError, /Symbol or Proc/)
      end
    end
  end

  describe "#completed?" do
    let(:loop_node) do
      described_class.new(:prior_employer, association: :prior_employers, pages: [ business_name_page, role_page ])
    end

    it "is true when every child record is valid on every loop page" do
      flow_record = EmploymentForm.new(prior_employers: [
        PriorEmployer.new(business_name: "Acme", role: "Engineer"),
        PriorEmployer.new(business_name: "Globex", role: "Manager")
      ])

      expect(loop_node).to be_completed(flow_record)
    end

    it "is false when any child record is invalid on any loop page" do
      flow_record = EmploymentForm.new(prior_employers: [
        PriorEmployer.new(business_name: "Acme", role: "Engineer"),
        PriorEmployer.new(business_name: "Globex", role: nil)
      ])

      expect(loop_node).not_to be_completed(flow_record)
    end

    it "is true (vacuously) when the relation is empty" do
      flow_record = EmploymentForm.new(prior_employers: [])

      expect(loop_node).to be_completed(flow_record)
    end

    it "only considers records inside the scope" do
      scoped_loop = described_class.new(
        :prior_employer,
        association: :prior_employers,
        pages: [ business_name_page, role_page ],
        scope: ->(records) { records.select { |r| r.business_name == "Acme" } }
      )

      flow_record = EmploymentForm.new(prior_employers: [
        PriorEmployer.new(business_name: "Acme", role: "Engineer"),
        PriorEmployer.new(business_name: "Globex", role: nil)
      ])

      # The Globex record is outside the scope, so its missing :role doesn't fail completion.
      expect(scoped_loop).to be_completed(flow_record)
    end
  end

  describe "#started?" do
    let(:loop_node) do
      described_class.new(:prior_employer, association: :prior_employers, pages: [ business_name_page, role_page ])
    end

    it "is true when any child record has any completed page" do
      flow_record = EmploymentForm.new(prior_employers: [
        PriorEmployer.new(business_name: "Acme")
      ])

      expect(loop_node).to be_started(flow_record)
    end

    it "is false when no child records exist" do
      flow_record = EmploymentForm.new(prior_employers: [])

      expect(loop_node).not_to be_started(flow_record)
    end

    it "is false when no child records have any completed page" do
      flow_record = EmploymentForm.new(prior_employers: [
        PriorEmployer.new
      ])

      expect(loop_node).not_to be_started(flow_record)
    end
  end
end
