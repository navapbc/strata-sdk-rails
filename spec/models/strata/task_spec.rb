# frozen_string_literal: true

require 'rails_helper'
require "support/matchers/publish_event_with_payload"

RSpec.describe Strata::Task, type: :model do
  let(:kase) { create(:test_case) }
  let(:task) { kase.create_task(described_class, description: Faker::Quote.yoda) }

  describe 'polymorphic associations' do
    let(:foo_case) { FooTestCase.create! }

    it 'belongs to a polymorphic case' do
      expect(task.case).to eq(kase)
      expect(task.case_type).to eq('TestCase')
    end

    it 'can be associated with different case types' do
      new_task = described_class.create!(case: foo_case)
      expect(new_task.case).to eq(foo_case)
      expect(new_task.case_type).to eq('FooTestCase')
    end

    it 'can find all tasks for a case' do
      task2 = described_class.create!(case: kase)
      expect(kase.tasks).to contain_exactly(task, task2)
    end

    it 'maintains case association through updates' do
      task.update!(description: 'Updated')
      expect(task.reload.case).to eq(kase)
    end

    it 'can be queried by case type' do
      foo_task = described_class.create!(case: foo_case)
      expect(described_class.where(case_type: 'TestCase')).to include(task)
      expect(described_class.where(case_type: 'FooTestCase')).to include(foo_task)
    end
  end

  context 'when attempting to set readonly attributes' do
    describe 'assignee_id attribute' do
      it 'cannot be modified directly' do
        expect { task.assignee_id = Faker::Number.non_zero_digit }.to raise_error(NoMethodError)
      end
    end

    describe 'case_id attribute' do
      it 'cannot be modified directly' do
        expect { task.case_id = Faker::Number.non_zero_digit }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      end
    end

    describe 'type attribute' do
      it 'cannot be modified directly' do
        expect { task.type = Faker::String.random(length: 3..30) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      end
    end
  end

  describe '#assign' do
    let(:user) { User.create!(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name) }

    it 'assigns the task to the given user' do
      assignee_id = user.id

      task.assign(assignee_id)
      task.reload # reload the task from the db to ensure it was properly assigned

      expect(task.assignee_id).to eq(assignee_id)
    end
  end

  describe '#unassign' do
    let(:user) { User.create!(first_name: Faker::Name.first_name, last_name: Faker::Name.last_name) }

    it 'removes the assignee from the task' do
      task.assign(user.id)

      task.unassign
      task.reload # reload the task from the db to ensure it was properly unassigned

      expect(task.assignee_id).to be_nil
    end
  end

  context "with enum methods" do
    describe '#completed' do
      it 'marks the task as completed' do
        task.completed!
        task.reload

        expect(task.status).to eq('completed')
        expect(task.completed?).to be true
      end

      it 'emits an event as completed' do
        expect { task.completed! }.to publish_event_with_payload("Strata::TaskCompleted", { task_id: task.id, case_id: task.case_id })
      end
    end

    describe '#pending' do
      it 'marks the task as pending' do
        task.pending!
        task.reload

        expect(task.status).to eq('pending')
        expect(task.pending?).to be true
      end

      it 'emits an event as pending' do
        task.completed! # Set it to completed first to ensure a status change

        expect { task.pending! }.to publish_event_with_payload("Strata::TaskPending", { task_id: task.id, case_id: task.case_id })
      end
    end

    describe '#on_hold' do
      it 'marks the task as on hold' do
        task.on_hold!
        task.reload

        expect(task.status).to eq('on_hold')
        expect(task.on_hold?).to be true
      end

      it 'emits an event as on hold' do
        task.pending! # Set it to pending first to ensure a status change

        expect { task.on_hold! }.to publish_event_with_payload("Strata::TaskOnHold", { task_id: task.id, case_id: task.case_id })
      end
    end
  end

  describe 'validations' do
    it 'validates presence of case on create' do
      expect { described_class.create! }.to raise_error(ActiveRecord::RecordInvalid, /Validation failed: Case must exist/)
    end
  end
end
