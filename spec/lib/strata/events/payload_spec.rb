# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Events::Payload do
  def round_trip(payload)
    described_class.deserialize(JSON.parse(described_class.serialize(payload).to_json))
  end

  describe '.serialize' do
    it 'returns a JSON-compatible hash' do
      serialized = described_class.serialize({ case_id: 'abc' })

      expect(JSON.parse(serialized.to_json)).to eq(serialized)
    end

    it 'stores a record as a GlobalID reference instead of its attributes' do
      kase = TestCase.create!(business_process_current_step: 'secret_step')

      serialized = described_class.serialize({ kase: kase })

      expect(serialized['kase']).to eq('_aj_globalid' => kase.to_global_id.to_s)
      expect(serialized.to_json).not_to include('secret_step')
    end

    it 'raises when ActiveJob cannot serialize a value' do
      allow(Rails.env).to receive(:local?).and_return(false)

      expect { described_class.serialize({ handler: Object.new }) }
        .to raise_error(ActiveJob::SerializationError)
    end

    it 'raises when the payload is not a hash' do
      expect { described_class.serialize([ 1, 2 ]) }.to raise_error(ArgumentError, /must be a Hash/)
    end

    context 'when running in development or test' do
      [
        nil, true, false, 'text', :symbol, 42, 1.5, BigDecimal('9.99'),
        Date.new(2026, 10, 13), Time.utc(2026, 10, 13), DateTime.new(2026, 10, 13),
        Time.zone.parse('2026-10-13 10:30')
      ].each do |value|
        it "allows #{value.class} values" do
          expect { described_class.serialize({ value: value }) }.not_to raise_error
        end
      end

      it 'allows persisted records' do
        kase = TestCase.create!

        expect { described_class.serialize({ kase: kase }) }.not_to raise_error
      end

      it 'allows nested hashes and arrays of allowed values' do
        payload = { ids: [ 'a', 'b' ], meta: { 'count' => 2, at: [ Date.new(2026, 1, 1) ] } }

        expect { described_class.serialize(payload) }.not_to raise_error
      end

      it 'rejects unsupported values and names their path' do
        expect { described_class.serialize({ meta: { range: (1..2) } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta\.range.*Range/)
      end

      it 'rejects unsaved records because they have no identifier' do
        expect { described_class.serialize({ kase: TestCase.new }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /kase/)
      end

      it 'rejects records that are not ActiveRecord models' do
        expect { described_class.serialize({ form: Strata::Address.new }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /form/)
      end
    end

    context 'when running in production' do
      before { allow(Rails.env).to receive(:local?).and_return(false) }

      it 'skips the identifier-only check so it cannot reject a submission' do
        expect { described_class.serialize({ range: (1..2) }) }.not_to raise_error
      end
    end
  end

  describe '.deserialize' do
    it 'preserves symbol keys' do
      expect(round_trip({ case_id: 'abc', nested: { task_id: 'def' } }))
        .to eq({ case_id: 'abc', nested: { task_id: 'def' } })
    end

    it 'preserves string keys' do
      expect(round_trip({ 'case_id' => 'abc' })).to eq({ 'case_id' => 'abc' })
    end

    it 'preserves indifferent access hashes' do
      result = round_trip(ActiveSupport::HashWithIndifferentAccess.new(case_id: 'abc'))

      expect(result).to be_a(ActiveSupport::HashWithIndifferentAccess)
      expect(result[:case_id]).to eq('abc')
    end

    it 'preserves time zone and sub-second precision' do
      submitted_at = Time.zone.parse('2026-10-13 10:30:00.123456')

      result = round_trip({ submitted_at: submitted_at })

      expect(result[:submitted_at]).to be_a(ActiveSupport::TimeWithZone)
      expect(result[:submitted_at]).to eq(submitted_at)
    end

    it 'preserves dates and decimals' do
      expect(round_trip({ on: Date.new(2026, 10, 13), amount: BigDecimal('9.99') }))
        .to eq({ on: Date.new(2026, 10, 13), amount: BigDecimal('9.99') })
    end

    it "loads a record's current state rather than a snapshot" do
      kase = TestCase.create!(business_process_current_step: 'first')
      serialized = described_class.serialize({ kase: kase })
      kase.update!(business_process_current_step: 'second')

      expect(described_class.deserialize(serialized)[:kase].business_process_current_step).to eq('second')
    end

    it 'raises ActiveJob::DeserializationError when a referenced record was deleted' do
      kase = TestCase.create!
      serialized = described_class.serialize({ kase: kase })
      kase.destroy!

      expect { described_class.deserialize(serialized) }.to raise_error(ActiveJob::DeserializationError)
    end

    context 'when the stored payload has been tampered with' do
      it 'rejects a serializer that is not registered with ActiveJob' do
        not_a_serializer = Class.new { def self.deserialize(_hash) = :pwned }
        stub_const('NotASerializer', not_a_serializer)
        allow(not_a_serializer).to receive(:deserialize).and_call_original

        expect { described_class.deserialize({ 'x' => { '_aj_serialized' => 'NotASerializer' } }) }
          .to raise_error(Strata::Events::Payload::UnsafePayloadError, /NotASerializer/)
        expect(not_a_serializer).not_to have_received(:deserialize)
      end

      it 'rejects an unregistered serializer nested inside an array' do
        payload = { 'x' => [ { 'y' => { '_aj_serialized' => 'Kernel' } } ] }

        expect { described_class.deserialize(payload) }
          .to raise_error(Strata::Events::Payload::UnsafePayloadError, /Kernel/)
      end

      it 'rejects a GlobalID that does not point to an ActiveRecord model' do
        not_a_model = Class.new { def self.find(_id) = :pwned }
        stub_const('NotAModel', not_a_model)
        allow(not_a_model).to receive(:find).and_call_original
        gid = "gid://#{GlobalID.app}/NotAModel/1"

        expect { described_class.deserialize({ 'x' => { '_aj_globalid' => gid } }) }
          .to raise_error(Strata::Events::Payload::UnsafePayloadError, /NotAModel/)
        expect(not_a_model).not_to have_received(:find)
      end

      it 'rejects a GlobalID for an unknown class' do
        gid = "gid://#{GlobalID.app}/NoSuchClass/1"

        expect { described_class.deserialize({ 'x' => { '_aj_globalid' => gid } }) }
          .to raise_error(Strata::Events::Payload::UnsafePayloadError, /NoSuchClass/)
      end
    end
  end
end
