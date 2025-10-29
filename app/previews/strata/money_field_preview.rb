# frozen_string_literal: true

module Strata
  # MoneyFieldPreview provides preview examples for the money_field component.
  # It demonstrates different states of the money input field including empty,
  # filled, and invalid states.
  #
  # This class is used with Lookbook to generate UI component previews
  # for the money_field form component.
  #
  # @example Viewing the filled state preview
  #   # In Lookbook UI
  #   # Navigate to Strata > MoneyFieldPreview > filled
  #
  class MoneyFieldPreview < Lookbook::Preview
    layout "strata/component_preview"

    def empty
      render template: "strata/previews/_money_field", locals: { model: TestRecord.new }
    end

    def filled
      model = TestRecord.new
      model.weekly_wage = Strata::Money.new(cents: 150050)
      render template: "strata/previews/_money_field", locals: { model: model }
    end

    def invalid
      model = TestRecord.new
      model.weekly_wage = Strata::Money.new(cents: -100)
      model.errors.add(:weekly_wage, "must be a positive number")
      render template: "strata/previews/_money_field", locals: { model: model }
    end
  end
end
