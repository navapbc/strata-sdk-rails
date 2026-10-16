# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Events::Payload do
  # Mirrors storing the serialized hash in a jsonb column and reading it back.
  def round_trip(payload)
    described_class.deserialize(JSON.parse(described_class.serialize(payload).to_json))
  end

  describe '.serialize' do
    it 'returns a hash with string keys that JSON stores unchanged' do
      serialized = described_class.serialize({ case_id: 'abc', nested: { task_id: 'def' } })

      expect(serialized).to eq({ 'case_id' => 'abc', 'nested' => { 'task_id' => 'def' } })
      expect(JSON.parse(serialized.to_json)).to eq(serialized)
    end

    it 'raises when the payload is not a hash' do
      expect { described_class.serialize([ 1, 2 ]) }
        .to raise_error(Strata::Events::Payload::InvalidPayloadError, /must be a Hash/)
    end

    describe 'allowed values' do
      [ nil, true, false, 'text', 42, 2**70 ].each do |value|
        it "allows #{value.inspect}" do
          expect(described_class.serialize({ value: value })).to eq({ 'value' => value })
        end
      end

      it 'allows nested hashes and arrays of allowed values' do
        payload = { ids: [ 'a', 'b' ], meta: { 'count' => 2, flags: [ true, { 'x' => nil } ] } }

        expect(described_class.serialize(payload))
          .to eq({ 'ids' => [ 'a', 'b' ], 'meta' => { 'count' => 2, 'flags' => [ true, { 'x' => nil } ] } })
      end

      it 'stores times as ISO 8601 UTC strings with microseconds' do
        submitted_at = Time.use_zone('UTC') { Time.zone.parse('2026-10-13 10:30:00.123456') }

        expect(described_class.serialize({ submitted_at: submitted_at }))
          .to eq({ 'submitted_at' => '2026-10-13T10:30:00.123456Z' })
      end

      it 'converts times in other zones to UTC so equal instants store identical strings' do
        submitted_at = Time.use_zone('America/New_York') { Time.zone.parse('2026-10-13 06:30:00.123456') }

        expect(described_class.serialize({ submitted_at: submitted_at }))
          .to eq({ 'submitted_at' => '2026-10-13T10:30:00.123456Z' })
      end

      it 'stores Time and DateTime values as ISO 8601 UTC strings' do
        payload = { a: Time.new(2026, 10, 13, 3, 2, 3, '+02:00'), b: DateTime.new(2026, 10, 13, 3, 2, 3, '+02:00') }

        expect(described_class.serialize(payload))
          .to eq({ 'a' => '2026-10-13T01:02:03.000000Z', 'b' => '2026-10-13T01:02:03.000000Z' })
      end

      it "leaves the publisher's times in their original zone" do
        time = Time.new(2026, 10, 13, 3, 2, 3, '+02:00')
        time_with_zone = Time.use_zone('America/New_York') { Time.zone.parse('2026-10-13 06:30:00') }

        described_class.serialize({ a: time, b: time_with_zone })

        expect(time.utc_offset).to eq(2 * 3600)
        expect(time_with_zone.to_time.utc_offset).to eq(-4 * 3600)
      end

      it 'stores frozen times' do
        time = Time.new(2026, 10, 13, 3, 2, 3, '+02:00').freeze

        expect(described_class.serialize({ at: time })).to eq({ 'at' => '2026-10-13T01:02:03.000000Z' })
      end

      it 'stores dates as ISO 8601 date strings' do
        expect(described_class.serialize({ on: Date.new(2026, 10, 13) })).to eq({ 'on' => '2026-10-13' })
      end

      it 'allows binary strings that are plain ASCII' do
        expect(described_class.serialize({ code: 'abc'.b })).to eq({ 'code' => 'abc' })
      end
    end

    describe 'rejected values' do
      {
        'a symbol, which would come back as a string' => :approved,
        'a Range' => (1..2),
        'an arbitrary object' => Object.new
      }.each do |description, value|
        it "rejects #{description} and names its path" do
          expect { described_class.serialize({ meta: { value: value } }) }
            .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta\.value.*#{value.class}/)
        end
      end

      it 'rejects a BigDecimal, which JSON cannot store exactly, and suggests cents or a string' do
        expect { described_class.serialize({ meta: { amount: BigDecimal('9.99') } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta\.amount.*BigDecimal.*cents.*string/)
      end

      it 'rejects records and asks for an identifier instead' do
        kase = TestCase.create!

        expect { described_class.serialize({ kase: kase }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /kase.*TestCase.*id/)
      end

      it 'names array indexes in the path' do
        expect { described_class.serialize({ items: [ 'a', :b ] }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /items\.1/)
      end

      [ 1.5, 1.0e15, Float::NAN ].each do |value|
        it "rejects the float #{value}, which jsonb cannot return reliably, and suggests an integer or string" do
          expect { described_class.serialize({ meta: { total: value } }) }
            .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta\.total.*integer or a string/)
        end
      end

      {
        'a NUL byte' => "a\u0000b",
        'invalid UTF-8' => "a\xFFb",
        'non-ASCII binary data' => "\xFF".b
      }.each do |description, text|
        it "rejects a string containing #{description}, which JSON or Postgres cannot store" do
          expect { described_class.serialize({ note: text }) }
            .to raise_error(Strata::Events::Payload::InvalidPayloadError, /note/)
        end
      end
    end

    describe 'keys' do
      it 'rejects keys that are not strings or symbols and names their path' do
        expect { described_class.serialize({ counts: { 1 => 'a' } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /counts.*Integer/)
      end

      it 'names only the class of an unsupported key, so record attributes stay out of logs' do
        kase = TestCase.create!(business_process_current_step: 'secret_step')

        expect { described_class.serialize({ meta: { kase => 1 } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError) { |error|
            expect(error.message).to include('TestCase')
            expect(error.message).not_to include('secret_step')
          }
      end

      it 'rejects a hash with both the symbol and string form of a key, which would collide' do
        expect { described_class.serialize({ meta: { case_id: 'a', 'case_id' => 'b' } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta.*case_id/)
      end

      it 'rejects a key containing a NUL byte' do
        expect { described_class.serialize({ meta: { "a\u0000" => 1 } }) }
          .to raise_error(Strata::Events::Payload::InvalidPayloadError, /meta/)
      end
    end
  end

  describe '.deserialize' do
    it 'returns symbol keys at every level, including hashes inside arrays' do
      expect(round_trip({ 'case_id' => 'abc', nested: { task_id: 'def' }, list: [ { 'id' => 1 } ] }))
        .to eq({ case_id: 'abc', nested: { task_id: 'def' }, list: [ { id: 1 } ] })
    end

    it 'preserves strings, integers, booleans, and nil' do
      payload = { s: 'text', i: 42, t: true, n: nil }

      expect(round_trip(payload)).to eq(payload)
    end

    it 'returns times as ISO 8601 strings that parse back to the same instant' do
      submitted_at = Time.use_zone('UTC') { Time.zone.parse('2026-10-13 10:30:00.123456') }

      result = round_trip({ submitted_at: submitted_at })

      expect(result[:submitted_at]).to eq('2026-10-13T10:30:00.123456Z')
      expect(Time.zone.parse(result[:submitted_at])).to eq(submitted_at)
    end

    it 'returns stored data as plain values without loading classes or records' do
      kase = TestCase.create!
      data = { 'x' => { '_aj_globalid' => kase.to_global_id.to_s }, 'y' => { '_aj_serialized' => 'Kernel' } }

      expect(described_class.deserialize(data))
        .to eq({ x: { _aj_globalid: kase.to_global_id.to_s }, y: { _aj_serialized: 'Kernel' } })
    end

    [ nil, 'x', [ 1 ] ].each do |data|
      it "raises when the stored data is a #{data.class} instead of a Hash" do
        expect { described_class.deserialize(data) }
          .to raise_error(Strata::Events::Payload::CorruptPayloadError, /must be a Hash/)
      end
    end
  end
end
