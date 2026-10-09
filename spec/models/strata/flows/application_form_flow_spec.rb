# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::ApplicationFormFlow do
  before do
    test_model_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :applicant_name_first, :string
      attribute :applicant_name_last, :string
      attribute :date_of_birth, :string
      attribute :leave_type, :string
    end

    test_flow_class = Class.new do
      include Strata::Flows::ApplicationFormFlow
      task :personal_information do
        question_page :name, fields: [ :applicant_name_first, :applicant_name_last ]
        question_page :date_of_birth
      end

      task :leave_details do
        question_page :leave_type
        question_page :supporting_documents, if: ->(app) { app.leave_type === "medical" }
      end

      end_page :review
    end

    stub_const("TestModel", test_model_class)
    stub_const("TestFlow", test_flow_class)
  end

  it "parses the task structure correctly" do
    expect(TestFlow.tasks.length).to eq(2)
    expect(TestFlow.tasks.map(&:name)).to eq([ :personal_information, :leave_details ])
    expect(TestFlow.tasks[0].pages.map(&:name)).to eq([ :name, :date_of_birth ])
    expect(TestFlow.tasks[1].pages.map(&:name)).to eq([ :leave_type, :supporting_documents ])

    expect(TestFlow.contexts).to eq([
      :name,
      :date_of_birth,
      :leave_type,
      :supporting_documents
    ])
    expect(TestFlow.end_pathname).to eq(:review)
  end

  describe "#find_page_and_task_by_action" do
    it "returns the page and task based on the action name" do
      page, task = TestFlow.find_page_and_task_by_action(TestModel.new, "edit_name")
      expect(page.name).to eq(:name)
      expect(task.task.name).to eq(:personal_information)
      expect(task.current_page_idx).to eq(0)
    end
  end

  describe "task dependencies" do
    before do
      flow_with_deps = Class.new do
        include Strata::Flows::ApplicationFormFlow

        task :personal_information do
          question_page :name, fields: [ :applicant_name_first, :applicant_name_last ]
        end

        task :leave_details, depends_on: [ :personal_information ] do
          question_page :leave_type
        end

        end_page :review
      end

      stub_const("FlowWithDeps", flow_with_deps)
    end

    it "stores depends_on on the task" do
      leave_task = FlowWithDeps.tasks.find { |t| t.name == :leave_details }
      expect(leave_task.depends_on).to eq([ :personal_information ])
    end

    it "stores nil depends_on when not specified" do
      personal_task = FlowWithDeps.tasks.find { |t| t.name == :personal_information }
      expect(personal_task.depends_on).to be_nil
    end

    describe "invalid depends_on references" do
      it "raises an error when task depends_on references a non-existent task" do
        expect {
          Class.new do
            include Strata::Flows::ApplicationFormFlow

            task :personal_information do
              question_page :name, fields: [ :applicant_name_first ]
            end

            task :review, depends_on: [ :nonexistent_task ] do
              question_page :date_of_birth
            end
          end
        }.to raise_error(ArgumentError, /nonexistent_task/)
      end
    end
  end

  describe "loop DSL" do
    before do
      flow_with_loop = Class.new do
        include Strata::Flows::ApplicationFormFlow

        task :personal_information do
          question_page :name, fields: [ :applicant_name_first ]
        end

        task :employment do
          question_page :employer_name
          loop :prior_employer, association: :prior_employers do
            question_page :business_name
            question_page :role
          end
          question_page :years_employed
        end

        task :leave_details do
          question_page :leave_type
        end

        end_page :review
      end

      stub_const("FlowWithLoop", flow_with_loop)
    end

    it "wraps loop pages in a Loop node within the task" do
      employment_task = FlowWithLoop.tasks.find { |t| t.name == :employment }

      expect(employment_task.pages.length).to eq(3)
      expect(employment_task.pages[0]).to be_a(Strata::Flows::QuestionPage)
      expect(employment_task.pages[0].name).to eq(:employer_name)

      loop_node = employment_task.pages[1]
      expect(loop_node).to be_a(Strata::Flows::Loop)
      expect(loop_node.name).to eq(:prior_employer)
      expect(loop_node.association).to eq(:prior_employers)
      expect(loop_node.pages.map(&:name)).to eq([ :business_name, :role ])

      expect(employment_task.pages[2]).to be_a(Strata::Flows::QuestionPage)
      expect(employment_task.pages[2].name).to eq(:years_employed)
    end

    it "defaults the loop's association to its name when omitted in the DSL" do
      flow_without_assoc = Class.new do
        include Strata::Flows::ApplicationFormFlow

        task :employment do
          loop :prior_employers do
            question_page :business_name
          end
        end
      end

      loop_node = flow_without_assoc.tasks.first.pages.first
      expect(loop_node).to be_a(Strata::Flows::Loop)
      expect(loop_node.name).to eq(:prior_employers)
      expect(loop_node.association).to eq(:prior_employers)
    end

    it "passes scope: through to the Loop node" do
      scope_proc = ->(rel) { rel }
      flow_with_scope = Class.new do
        include Strata::Flows::ApplicationFormFlow

        task :employment do
          loop :prior_employer, association: :prior_employers, scope: :active do
            question_page :business_name
          end
        end
      end

      flow_with_scope_proc = Class.new do
        include Strata::Flows::ApplicationFormFlow

        task :employment do
          loop :prior_employer, association: :prior_employers, scope: scope_proc do
            question_page :business_name
          end
        end
      end

      expect(flow_with_scope.tasks.first.pages.first.scope).to eq(:active)
      expect(flow_with_scope_proc.tasks.first.pages.first.scope).to eq(scope_proc)
    end

    it "back-references the loop on each enclosed QuestionPage" do
      loop_node = FlowWithLoop.tasks.find { |t| t.name == :employment }.pages[1]

      expect(loop_node.pages).to all(be_in_loop)
      expect(loop_node.pages.map(&:loop).uniq).to eq([ loop_node ])
    end

    it "registers loop page names in the flow contexts (un-namespaced)" do
      expect(FlowWithLoop.contexts).to include(:business_name, :role)
    end

    describe "#all_pages" do
      it "returns the flat sequence of QuestionPages, expanding loops in place" do
        names = FlowWithLoop.all_pages.map(&:name)
        expect(names).to eq([
          :name,
          :employer_name,
          :business_name,
          :role,
          :years_employed,
          :leave_type
        ])
      end
    end

    describe "#generated_routes" do
      it "includes namespaced action names for loop pages" do
        expect(FlowWithLoop.generated_routes).to include(
          "edit_prior_employer_business_name",
          "update_prior_employer_business_name",
          "edit_prior_employer_role",
          "update_prior_employer_role"
        )
      end

      it "keeps un-namespaced action names for top-level pages" do
        expect(FlowWithLoop.generated_routes).to include(
          "edit_name", "update_name",
          "edit_employer_name", "update_employer_name",
          "edit_years_employed", "update_years_employed",
          "edit_leave_type", "update_leave_type"
        )
      end
    end

    describe "#find_page_and_task_by_action" do
      let(:flow_record) do
        Class.new do
          attr_accessor :prior_employers

          def initialize(prior_employers: [])
            @prior_employers = prior_employers
          end
        end.new
      end

      it "finds top-level pages by un-namespaced action" do
        page, evaluator = FlowWithLoop.find_page_and_task_by_action(flow_record, "edit_employer_name")

        expect(page.name).to eq(:employer_name)
        expect(evaluator.task.name).to eq(:employment)
      end

      it "finds loop pages by namespaced action and returns a loop-aware evaluator" do
        child_record = Object.new
        relation = Class.new do
          def initialize(record)
            @record = record
          end

          def find(_id)
            @record
          end
        end.new(child_record)
        flow_record.prior_employers = relation

        page, evaluator = FlowWithLoop.find_page_and_task_by_action(
          flow_record,
          "edit_prior_employer_business_name",
          "xyz"
        )

        expect(page.name).to eq(:business_name)
        expect(page).to be_in_loop
        expect(evaluator.task.name).to eq(:employment)
        expect(evaluator.loop_record).to eq(child_record)
      end

      it "returns nil when the action does not match any page" do
        page, evaluator = FlowWithLoop.find_page_and_task_by_action(flow_record, "edit_unknown")

        expect(page).to be_nil
        expect(evaluator).to be_nil
      end
    end

    describe "collision detection" do
      it "raises when two loop pages would generate the same namespaced action" do
        expect {
          Class.new do
            include Strata::Flows::ApplicationFormFlow

            task :employment do
              loop :prior_employer, association: :prior_employers do
                question_page :business_name
                question_page :business_name
              end
            end
          end
        }.to raise_error(ArgumentError, /duplicate.*business_name/i)
      end

      it "raises when a loop page collides with a top-level page after namespacing" do
        expect {
          Class.new do
            include Strata::Flows::ApplicationFormFlow

            task :employment do
              question_page :prior_employer_business_name
              loop :prior_employer, association: :prior_employers do
                question_page :business_name
              end
            end
          end
        }.to raise_error(ArgumentError, /duplicate.*prior_employer_business_name/i)
      end
    end
  end
end
