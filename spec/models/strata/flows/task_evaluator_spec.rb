# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::TaskEvaluator do
  before do
    test_model_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes

      attribute :first_name, :string
    end

    stub_const("TestModel", test_model_class)
  end

  let(:record) { TestModel.new }
  let(:task) do
    Strata::Flows::Task.new("personal_information", pages: [
      Strata::Flows::QuestionPage.new("first_name"),
      Strata::Flows::QuestionPage.new("middle_name", if: ->(record) { record.first_name === "John" }),
      Strata::Flows::QuestionPage.new("last_name")
    ])
  end

  let(:eval) { described_class.new(task, record, current_page_idx) }

  describe "#current_page" do
    let(:current_page_idx) { 2 }

    it "returns the current page" do
      expect(eval.current_page.name).to eq("last_name")
    end
  end

  describe "#prev_path" do
    describe "on the first page" do
      let(:current_page_idx) { 0 }

      it "returns nil" do
        expect(eval.prev_path).to be_nil
      end
    end

    describe "on other pages" do
      let(:current_page_idx) { 2 }

      it "returns the previous path" do
        record.first_name = "John"
        allow(task.pages[1]).to receive(:edit_path).and_return("edit_path")
        expect(eval.prev_path).to eq("edit_path")
      end

      it "ignores unnecessary pages" do
        allow(task.pages[0]).to receive(:edit_path).and_return("edit_path")
        expect(eval.prev_path).to eq("edit_path")
      end
    end
  end

  describe "#update_path" do
    let(:current_page_idx) { 0 }

    it "returns the update path for the current page" do
      allow(task.pages[0]).to receive(:update_path).and_return("update_path")
      expect(eval.update_path).to eq("update_path")
    end
  end

  describe "#next_path" do
    describe "on the last page" do
      let(:current_page_idx) { 2 }

      it "returns nil" do
        expect(eval.next_path).to be_nil
      end
    end

    describe "on other pages" do
      let(:current_page_idx) { 0 }

      it "returns the next path" do
        record.first_name = "John"
        allow(task.pages[1]).to receive(:edit_path).and_return("edit_path")
        expect(eval.next_path).to eq("edit_path")
      end

      it "ignores unnecessary pages" do
        allow(task.pages[2]).to receive(:edit_path).and_return("edit_path")
        expect(eval.next_path).to eq("edit_path")
      end
    end
  end

  describe "traversal across a loop" do
    let(:outer_before) { Strata::Flows::QuestionPage.new(:employer_name) }
    let(:loop_business_name) { Strata::Flows::QuestionPage.new(:business_name) }
    let(:loop_role) { Strata::Flows::QuestionPage.new(:role) }
    let(:loop_node) do
      Strata::Flows::Loop.new(
        :prior_employer,
        association: :prior_employers,
        pages: [ loop_business_name, loop_role ]
      )
    end
    let(:outer_after) { Strata::Flows::QuestionPage.new(:years_employed) }
    let(:task) do
      Strata::Flows::Task.new(:employment, pages: [ outer_before, loop_node, outer_after ])
    end
    let(:child_a) { PriorEmployer.new(business_name: "Acme") }
    let(:child_b) { PriorEmployer.new(business_name: "Globex") }
    let(:flow_record) { EmploymentForm.new(prior_employers: [ child_a, child_b ]) }

    before do
      child_class = Class.new do
        include ActiveModel::Model
        include ActiveModel::Attributes
        attribute :business_name, :string
        attribute :role, :string
      end

      parent_class = Class.new do
        include ActiveModel::Model
        attr_accessor :prior_employers, :employer_name, :years_employed

        def initialize(prior_employers: [], employer_name: nil, years_employed: nil)
          @prior_employers = prior_employers
          @employer_name = employer_name
          @years_employed = years_employed
        end
      end

      stub_const("PriorEmployer", child_class)
      stub_const("EmploymentForm", parent_class)

      # Back-reference loop pages to their loop (implementation does this via the
      # DSL when constructing the Loop; here we wire it manually).
      [ loop_business_name, loop_role ].each { |p| p.loop = loop_node }
    end

    describe "#next_path on the outer page before the loop" do
      it "enters the loop at the first loop page for the first child record" do
        allow(loop_business_name).to receive(:edit_path).with(flow_record, child_a).and_return("/loop/a/business_name")
        cursor = described_class.new(task, flow_record, 0)

        expect(cursor.next_path).to eq("/loop/a/business_name")
      end

      it "skips the loop and continues to the next outer page when the relation is empty" do
        empty_flow_record = EmploymentForm.new(prior_employers: [])
        allow(outer_after).to receive(:edit_path).with(empty_flow_record).and_return("/years_employed")
        cursor = described_class.new(task, empty_flow_record, 0)

        expect(cursor.next_path).to eq("/years_employed")
      end
    end

    describe "#next_path inside the loop (not the last page)" do
      it "advances to the next loop page for the same child record" do
        allow(loop_role).to receive(:edit_path).with(flow_record, child_a).and_return("/loop/a/role")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 0)

        expect(cursor.next_path).to eq("/loop/a/role")
      end
    end

    describe "#next_path on the last loop page" do
      it "advances to the first loop page for the next child record" do
        allow(loop_business_name).to receive(:edit_path).with(flow_record, child_b).and_return("/loop/b/business_name")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 1)

        expect(cursor.next_path).to eq("/loop/b/business_name")
      end

      it "exits the loop to the next outer page when on the last child's last loop page" do
        allow(outer_after).to receive(:edit_path).with(flow_record).and_return("/years_employed")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_b, loop_page_idx: 1)

        expect(cursor.next_path).to eq("/years_employed")
      end

      it "returns nil when there is no outer page after the loop and we are on the last child's last loop page" do
        task_without_after = Strata::Flows::Task.new(:employment, pages: [ outer_before, loop_node ])
        cursor = described_class.new(task_without_after, flow_record, 1, loop_record: child_b, loop_page_idx: 1)

        expect(cursor.next_path).to be_nil
      end
    end

    describe "#next_path with a scoped loop" do
      let(:loop_node) do
        Strata::Flows::Loop.new(
          :prior_employer,
          association: :prior_employers,
          pages: [ loop_business_name, loop_role ],
          scope: ->(records) { records.select { |r| r.business_name == "Acme" } }
        )
      end

      it "treats out-of-scope records as if they don't exist when advancing past the loop" do
        # child_b is filtered out by the scope; cursor at child_a's last page exits the loop.
        allow(outer_after).to receive(:edit_path).with(flow_record).and_return("/years_employed")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 1)

        expect(cursor.next_path).to eq("/years_employed")
      end

      it "enters the loop at the first in-scope record from the outer page" do
        allow(loop_business_name).to receive(:edit_path).with(flow_record, child_a).and_return("/loop/a/business_name")
        cursor = described_class.new(task, flow_record, 0)

        expect(cursor.next_path).to eq("/loop/a/business_name")
      end
    end

    describe "#next_path with if: predicates inside the loop" do
      let(:loop_role) do
        Strata::Flows::QuestionPage.new(:role, if: ->(child) { child.business_name == "Globex" })
      end

      it "skips a loop page for a child whose predicate is false, advancing to the next child" do
        # child_a.business_name == "Acme", so :role is skipped for child_a; advance to child_b's first page
        allow(loop_business_name).to receive(:edit_path).with(flow_record, child_b).and_return("/loop/b/business_name")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 0)

        expect(cursor.next_path).to eq("/loop/b/business_name")
      end
    end

    describe "#prev_path inside the loop" do
      it "returns the previous loop page for the same child record" do
        allow(loop_business_name).to receive(:edit_path).with(flow_record, child_a).and_return("/loop/a/business_name")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 1)

        expect(cursor.prev_path).to eq("/loop/a/business_name")
      end

      it "wraps back to the previous child's last loop page when on the first loop page of a non-first child" do
        allow(loop_role).to receive(:edit_path).with(flow_record, child_a).and_return("/loop/a/role")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_b, loop_page_idx: 0)

        expect(cursor.prev_path).to eq("/loop/a/role")
      end

      it "exits the loop backwards to the outer page when on the first child's first loop page" do
        allow(outer_before).to receive(:edit_path).with(flow_record).and_return("/employer_name")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 0)

        expect(cursor.prev_path).to eq("/employer_name")
      end
    end

    describe "#prev_path on the outer page after the loop" do
      it "enters the loop backwards at the last loop page of the last child record" do
        allow(loop_role).to receive(:edit_path).with(flow_record, child_b).and_return("/loop/b/role")
        cursor = described_class.new(task, flow_record, 2)

        expect(cursor.prev_path).to eq("/loop/b/role")
      end

      it "skips an empty loop and returns the outer page before it" do
        empty_flow_record = EmploymentForm.new(prior_employers: [])
        allow(outer_before).to receive(:edit_path).with(empty_flow_record).and_return("/employer_name")
        cursor = described_class.new(task, empty_flow_record, 2)

        expect(cursor.prev_path).to eq("/employer_name")
      end
    end

    describe "#current_page" do
      it "returns the loop page when the cursor is inside a loop" do
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 1)
        expect(cursor.current_page).to eq(loop_role)
      end

      it "returns the outer page when the cursor is outside a loop" do
        cursor = described_class.new(task, flow_record, 0)
        expect(cursor.current_page).to eq(outer_before)
      end
    end

    describe "#update_path" do
      it "returns the namespaced update_path with parent and child for a loop page" do
        allow(loop_business_name).to receive(:update_path).with(flow_record, child_a).and_return("/loop/a/update_business_name")
        cursor = described_class.new(task, flow_record, 1, loop_record: child_a, loop_page_idx: 0)

        expect(cursor.update_path).to eq("/loop/a/update_business_name")
      end
    end
  end
end
