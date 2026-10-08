# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'strata:events', type: :task do
  let(:event_manager) { class_double(Strata::EventManager) }
  let(:failures) do
    [
      { subscriber: 'SomeBusinessProcess.handle_event', error: StandardError.new('step failed') },
      { subscriber: 'Proc', error: ArgumentError.new('lambda failed') }
    ]
  end

  before do
    Rake.application.rake_require('tasks/strata_events')
    Rake::Task.define_task(:environment)
    stub_const('Strata::EventManager', event_manager)
    allow(Strata::EventManager).to receive(:publish).and_return([])
  end

  describe 'publish_event' do
    let(:task) { Rake::Task['strata:events:publish_event'] }

    after do
      task.reenable
    end

    describe 'argument validation' do
      it 'raises error if event_name is missing' do
        expect {
          task.invoke(nil)
        }.to raise_error(/event_name is required/)
      end
    end

    describe 'successful event emission' do
      before do
        allow(Rails.logger).to receive(:info)
      end

      it 'publishes the event and outputs a message' do
        event_name = Faker::Alphanumeric.alpha(number: rand(5..15))

        task.invoke(event_name)

        expect(Strata::EventManager).to have_received(:publish).with(event_name)
        expect(Rails.logger).to have_received(:info).with(/Event '#{event_name}' published/)
      end
    end

    describe 'when a subscriber fails' do
      before do
        allow(Strata::EventManager).to receive(:publish).and_return(failures)
      end

      it 'exits non-zero and names each failed subscriber and its error' do
        expect {
          task.invoke('SomethingHappened')
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(
            a_string_including(
              "Event 'SomethingHappened'",
              'SomeBusinessProcess.handle_event', 'StandardError', 'step failed',
              'Proc', 'ArgumentError', 'lambda failed'
            )
          ).to_stderr
      end
    end
  end

  describe 'publish_case_event' do
    let(:task) { Rake::Task['strata:events:publish_case_event'] }

    after do
      task.reenable
    end

    describe 'argument validation' do
      it 'raises error if event_name is missing' do
        expect {
          task.invoke(nil, "TestCase", Faker::Number.digit)
        }.to raise_error(/event_name is required/)
      end

      it 'raises error if case_class is missing' do
        expect {
          task.invoke(Faker::Alphanumeric.alpha(number: 10), nil, Faker::Number.digit)
        }.to raise_error(/case_class is required/)
      end

      it 'raises error if case_id is missing' do
        expect {
          task.invoke(Faker::Alphanumeric.alpha(number: 10), "TestCase", nil)
        }.to raise_error(/case_id is required/)
      end

      it 'raises error if all are missing' do
        expect {
          task.invoke(nil, nil, nil)
        }.to raise_error(/event_name, case_class, and case_id are required/)
      end
    end

    describe 'successful event emission' do
      let(:test_case) { instance_double(TestCase) }

      before do
        allow(Rails.logger).to receive(:info)
        allow(TestCase).to receive(:find).and_return(test_case)
      end

      it 'finds the case, publishes the event, and outputs a message' do
        event_name = Faker::Alphanumeric.alpha(number: rand(5..15))
        case_id = Faker::Number.between(from: 1, to: 1000)

        task.invoke(event_name, "TestCase", case_id)

        expect(Strata::EventManager).to have_received(:publish).with(event_name, hash_including(kase: test_case))
        expect(Rails.logger).to have_received(:info).with(/Event '#{event_name}' published for 'TestCase' with ID '#{case_id}'/)
      end
    end

    describe 'when a subscriber fails' do
      before do
        allow(TestCase).to receive(:find).and_return(instance_double(TestCase))
        allow(Strata::EventManager).to receive(:publish).and_return(failures)
      end

      it 'exits non-zero and names the case and each failed subscriber and its error' do
        expect {
          task.invoke('SomethingHappened', 'TestCase', '123')
        }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          .and output(
            a_string_including(
              "Event 'SomethingHappened'", "'TestCase'", "'123'",
              'SomeBusinessProcess.handle_event', 'StandardError', 'step failed',
              'Proc', 'ArgumentError', 'lambda failed'
            )
          ).to_stderr
      end
    end
  end
end
