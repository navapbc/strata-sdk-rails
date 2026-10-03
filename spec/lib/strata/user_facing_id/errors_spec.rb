# frozen_string_literal: true

require "rails_helper"

RSpec.describe Strata::UserFacingId::Error do
  it "is the root for all user-facing ID codec errors" do
    expect(Strata::UserFacingId::FormatError.ancestors).to include(described_class)
    expect(Strata::UserFacingId::ParityError.ancestors).to include(described_class)
  end

  it "inherits ArgumentError so callers can rescue at that broader level" do
    # The attribute's permissive cast path rescues Strata::UserFacingId::Error, but
    # external callers may rescue ArgumentError; both must catch every codec error.
    expect(described_class.ancestors).to include(ArgumentError)
    expect(Strata::UserFacingId::FormatError.ancestors).to include(ArgumentError)
    expect(Strata::UserFacingId::ParityError.ancestors).to include(ArgumentError)
  end

  it "lets a single rescue clause catch both error subclasses" do
    rescued = [
      begin
        raise Strata::UserFacingId::FormatError, "format"
      rescue described_class => e
        e.class
      end,
      begin
        raise Strata::UserFacingId::ParityError, "parity"
      rescue described_class => e
        e.class
      end
    ]

    expect(rescued).to eq([ Strata::UserFacingId::FormatError, Strata::UserFacingId::ParityError ])
  end
end
