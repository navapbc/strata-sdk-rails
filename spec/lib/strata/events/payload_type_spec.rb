# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Events::PayloadType do
  subject(:type) { described_class.new }

  describe '#cast' do
    it 'serializes assigned payloads to the plain JSON contract' do
      expect(type.cast({ case_id: 'abc', on: Date.new(2026, 10, 14) }))
        .to eq({ 'case_id' => 'abc', 'on' => '2026-10-14' })
    end

    it 'raises for payloads that break the contract' do
      expect { type.cast({ score: Float::NAN }) }
        .to raise_error(Strata::Events::Payload::InvalidPayloadError, /score/)
    end

    it 'raises for nil' do
      expect { type.cast(nil) }.to raise_error(Strata::Events::Payload::InvalidPayloadError, /must be a Hash/)
    end
  end

  describe '#deserialize' do
    it 'reads stored JSON without checking it again' do
      expect(type.deserialize('{"case_id":"abc"}')).to eq({ 'case_id' => 'abc' })
    end
  end
end
