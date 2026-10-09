# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::Task do
  before do
    test_model_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :first_name, :string
      validates :first_name, presence: true, on: :first_name
    end

    stub_const("TestModel", test_model_class)
  end

  let(:incomplete_page) { Strata::Flows::QuestionPage.new("first_name") }
  let(:complete_page) { Strata::Flows::QuestionPage.new("last_name") }
  let(:record) { TestModel.new }

  describe "an unstarted task" do
    let(:task) { described_class.new("name", pages: [ incomplete_page ]) }

    it "is not started or completed" do
      expect(task).not_to be_started(record)
      expect(task).not_to be_completed(record)
    end

    it "returns the first page path" do
      allow(incomplete_page).to receive(:edit_path).and_return("edit_path")
      expect(task.path(record)).to eq("edit_path")
    end
  end

  describe "a started task" do
    let(:task) { described_class.new("name", pages: [ complete_page, incomplete_page ]) }

    it "is started but not completed" do
      expect(task).to be_started(record)
      expect(task).not_to be_completed(record)
    end

    it "returns the first incomplete page path" do
      allow(incomplete_page).to receive(:edit_path).and_return("edit_path")
      expect(task.path(record)).to eq("edit_path")
    end
  end

  describe "a completed task" do
    let(:task) { described_class.new("name", pages: [ complete_page ]) }

    it "is started and completed" do
      expect(task).to be_started(record)
      expect(task).to be_completed(record)
    end

    it "returns the first page path" do
      allow(complete_page).to receive(:edit_path).and_return("edit_path")
      expect(task.path(record)).to eq("edit_path")
    end
  end

  describe "a task containing a loop" do
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
        attr_accessor :prior_employers, :first_name

        def initialize(prior_employers: [], first_name: nil)
          @prior_employers = prior_employers
          @first_name = first_name
        end
      end

      stub_const("PriorEmployer", child_class)
      stub_const("EmploymentForm", parent_class)
    end

    let(:outer_page) { Strata::Flows::QuestionPage.new(:first_name) }
    let(:loop_node) do
      Strata::Flows::Loop.new(
        :prior_employer,
        association: :prior_employers,
        pages: [
          Strata::Flows::QuestionPage.new(:business_name),
          Strata::Flows::QuestionPage.new(:role)
        ]
      )
    end
    let(:task) { described_class.new(:employment, pages: [ outer_page, loop_node ]) }

    it "is started when the outer page is started" do
      flow_record = EmploymentForm.new(first_name: "Mary", prior_employers: [])

      expect(task).to be_started(flow_record)
    end

    it "is started when any child record has any completed loop page" do
      flow_record = EmploymentForm.new(
        prior_employers: [ PriorEmployer.new(business_name: "Acme") ]
      )

      expect(task).to be_started(flow_record)
    end

    it "is completed when the outer page and every child loop page are valid" do
      flow_record = EmploymentForm.new(
        first_name: "Mary",
        prior_employers: [
          PriorEmployer.new(business_name: "Acme", role: "Engineer"),
          PriorEmployer.new(business_name: "Globex", role: "Manager")
        ]
      )

      expect(task).to be_completed(flow_record)
    end

    it "is not completed when a child record fails a loop page" do
      flow_record = EmploymentForm.new(
        first_name: "Mary",
        prior_employers: [
          PriorEmployer.new(business_name: "Acme", role: "Engineer"),
          PriorEmployer.new(business_name: "Globex")
        ]
      )

      expect(task).not_to be_completed(flow_record)
    end

    it "is completed when the loop relation is empty and the outer page is valid" do
      flow_record = EmploymentForm.new(first_name: "Mary", prior_employers: [])

      expect(task).to be_completed(flow_record)
    end
  end

  describe "#dependencies_met?" do
    let(:complete_task) { described_class.new(:personal_info) }
    let(:incomplete_task) { described_class.new(:contact_info) }
    let(:flow) { SampleFlow.new(build_stubbed(:sample_application_form)) }

    before do
      allow(complete_task).to receive(:completed?).and_return(true)
      allow(incomplete_task).to receive(:completed?).and_return(false)
    end

    context "with no depends_on" do
      let(:task) { described_class.new(:review) }

      it "returns true" do
        allow(flow).to receive(:tasks).and_return([ complete_task, incomplete_task, task ])
        expect(task.dependencies_met?(flow)).to be true
      end
    end

    context "with depends_on: :all" do
      let(:task) { described_class.new(:review, depends_on: :all) }

      it "returns true when all other tasks are complete" do
        allow(flow).to receive(:tasks).and_return([ complete_task, task ])
        expect(task.dependencies_met?(flow)).to be true
      end

      it "returns false when any other task is incomplete" do
        allow(flow).to receive(:tasks).and_return([ complete_task, incomplete_task, task ])
        expect(task.dependencies_met?(flow)).to be false
      end
    end

    context "with depends_on: [:specific_tasks]" do
      let(:task) { described_class.new(:review, depends_on: [ :personal_info ]) }

      it "returns true when named dependencies are complete" do
        allow(flow).to receive(:tasks).and_return([ complete_task, incomplete_task, task ])
        expect(task.dependencies_met?(flow)).to be true
      end

      it "returns false when a named dependency is incomplete" do
        task_with_dep = described_class.new(:review, depends_on: [ :contact_info ])
        allow(flow).to receive(:tasks).and_return([ complete_task, incomplete_task, task_with_dep ])
        expect(task_with_dep.dependencies_met?(flow)).to be false
      end
    end
  end
end
