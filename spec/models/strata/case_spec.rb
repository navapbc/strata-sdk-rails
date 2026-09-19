# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Case, type: :model do
  let(:test_case) { TestCase.new }

  describe '#create_task' do
    before do
      stub_const('TestTask', Class.new(Strata::Task))
      stub_const('NotATask', Class.new)
    end

    it 'creates a task associated with the case' do
      description = Faker::Quote.yoda
      task = test_case.create_task(TestTask, description: description)

      expect(task).to be_a(TestTask)
      expect(task.case).to eq(test_case)
      expect(task.description).to eq(description)
      expect(task).to be_persisted
    end

    it 'accepts additional attributes' do
      due_date = Faker::Date.between(from: Date.today, to: Date.today + 1.year)
      description = Faker::Quote.yoda
      task = test_case.create_task(TestTask,
        description: description,
        due_on: due_date
      )

      expect(task.due_on).to eq(due_date)
      expect(task.description).to eq(description)
      expect(task).to be_persisted
    end

    it 'raises an error if task_class is not a subclass of Strata::Task' do
      expect {
        test_case.create_task(NotATask)
      }.to raise_error(ArgumentError, 'task_class must be Strata::Task or a subclass of it')
    end
  end

  describe 'status attribute' do
    it 'defaults to open' do
      expect(test_case.status).to eq('open')
    end

    it 'can be closed using the close method' do
      test_case.close
      expect(test_case.status).to eq('closed')
    end

    it 'can be reopened using the reopen method' do
      test_case.close
      test_case.reopen
      expect(test_case.status).to eq('open')
    end

    it 'cannot be directly modified from outside the class' do
      expect { test_case.status = :closed }.to raise_error(NoMethodError)
    end
  end

  describe '#close!' do
    it 'closes the case and persists the change' do
      test_case.save!
      test_case.close!
      expect(test_case.status).to eq('closed')
      expect(test_case.reload.status).to eq('closed')
    end

    it 'raises an error when save fails' do
      test_case.save!

      # Make the case invalid by stubbing validation
      allow(test_case).to receive(:valid?).and_return(false)
      allow(test_case.errors).to receive(:full_messages).and_return([ 'Validation failed' ])

      expect { test_case.close! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#reopen!' do
    it 'reopens the case and persists the change' do
      test_case.save!
      test_case.close!
      test_case.reopen!
      expect(test_case.status).to eq('open')
      expect(test_case.reload.status).to eq('open')
    end

    it 'raises an error when save fails' do
      test_case.save!
      test_case.close!

      # Make the case invalid by stubbing validation
      allow(test_case).to receive(:valid?).and_return(false)
      allow(test_case.errors).to receive(:full_messages).and_return([ 'Validation failed' ])

      expect { test_case.reopen! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '.for_event scope' do
    let(:test_case) { create(:test_case) }

    context 'when event has case_id' do
      it 'returns cases with matching case_id' do
        event = { payload: { case_id: test_case.id } }
        expect(TestCase.for_event(event).to_a).to eq([ test_case ])
      end

      it 'raises ArgumentError when case_id is nil' do
        event = { payload: { case_id: nil } }
        expect {
          TestCase.for_event(event)
        }.to raise_error(ArgumentError, 'case_id cannot be nil')
      end
    end

    context 'when event has application_form_id' do
      it 'returns cases with matching application_form_id' do
        event = { payload: { application_form_id: test_case.application_form_id } }
        expect(TestCase.for_event(event).to_a).to eq([ test_case ])
      end

      it 'raises ArgumentError when application_form_id is nil' do
        event = { payload: { application_form_id: nil } }
        expect {
          TestCase.for_event(event)
        }.to raise_error(ArgumentError, 'application_form_id cannot be nil')
      end
    end

    context 'when event has neither case_id nor application_form_id' do
      it 'returns none' do
        event = { payload: {} }
        expect(TestCase.for_event(event)).to eq(TestCase.none)
      end
    end

    # Covers Phase 1 item 1.4, per spec.md 6.3. for_event tests
    # `payload.key?(:case_id)` with symbol keys, so any serialization that
    # stringifies keys makes it return none for every event — every delivery
    # succeeds, no case moves, and nothing raises. This is the failure mode
    # most likely to survive a code review, so the contract is pinned here
    # before Phase 2 touches serialization.
    context 'when the payload uses string keys instead of symbols' do
      {
        'case_id' => :id,
        'application_form_id' => :application_form_id
      }.each do |payload_key, attribute|
        it "does not match on #{payload_key}, which is why serialization must preserve symbol keys" do
          event = { payload: { payload_key => test_case.public_send(attribute) } }

          expect(TestCase.for_event(event)).to eq(TestCase.none)
        end
      end

      it 'does not raise on a nil value either, because the key is never seen' do
        event = { payload: { 'case_id' => nil } }

        expect { TestCase.for_event(event) }.not_to raise_error
      end
    end
  end

  describe '.actionable scope' do
    it 'returns cases that are in staff task steps' do
      # Create cases in different steps
      staff_case1 = create(:test_case)
      staff_case1.update!(business_process_current_step: 'staff_task')

      staff_case2 = create(:test_case)
      staff_case2.update!(business_process_current_step: 'staff_task_2')

      system_case = create(:test_case)
      system_case.update!(business_process_current_step: 'system_process')

      applicant_case = create(:test_case)
      applicant_case.update!(business_process_current_step: 'applicant_task')

      third_party_case = create(:test_case)
      third_party_case.update!(business_process_current_step: 'third_party_task')

      actionable_cases = TestCase.actionable.to_a

      expect(actionable_cases).to include(staff_case1, staff_case2)
      expect(actionable_cases).not_to include(system_case, applicant_case, third_party_case)
    end
  end

  describe '.migrate_business_process_current_step' do
    let(:from_step) { Faker::Alphanumeric.alpha(number: rand(5..15)) }
    let(:to_step) { Faker::Alphanumeric.alpha(number: rand(5..15)) }
    let(:other_step) { Faker::Alphanumeric.alpha(number: rand(5..15)) }

    it 'updates all cases with matching business_process_current_step' do
      case1 = create(:test_case)
      case1.update!(business_process_current_step: from_step)
      case2 = create(:test_case)
      case2.update!(business_process_current_step: from_step)
      case3 = create(:test_case)
      case3.update!(business_process_current_step: other_step)

      updated_count = TestCase.migrate_business_process_current_step(
        from_step_name: from_step,
        to_step_name: to_step
      )

      expect(updated_count).to eq(2)
      expect(case1.reload.business_process_current_step).to eq(to_step)
      expect(case2.reload.business_process_current_step).to eq(to_step)
      expect(case3.reload.business_process_current_step).to eq(other_step)
    end

    it 'returns 0 when no cases match' do
      case1 = create(:test_case)
      case1.update!(business_process_current_step: other_step)

      updated_count = TestCase.migrate_business_process_current_step(
        from_step_name: from_step,
        to_step_name: to_step
      )

      expect(updated_count).to eq(0)
      expect(case1.reload.business_process_current_step).to eq(other_step)
    end

    it 'does not update cases with nil business_process_current_step' do
      case1 = create(:test_case)
      case1.update!(business_process_current_step: nil)
      case2 = create(:test_case)
      case2.update!(business_process_current_step: from_step)

      updated_count = TestCase.migrate_business_process_current_step(
        from_step_name: from_step,
        to_step_name: to_step
      )

      expect(updated_count).to eq(1)
      expect(case1.reload.business_process_current_step).to be_nil
      expect(case2.reload.business_process_current_step).to eq(to_step)
    end
  end
end
