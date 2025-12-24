# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::FormBuilder do
  before do
    test_form_class = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include Strata::Attributes

      attribute :first_name, :string
      attribute :start_date, :date  # for date_picker
    end

    stub_const("TestForm", test_form_class)
  end


  let(:template) { ActionView::Base.empty }
  let(:object) { TestForm.new }
  let(:builder) { described_class.new(:object, object, template, {}) }

  describe '#text_field' do
    let(:result) { builder.text_field(:first_name, label: 'Name') }

    it 'outputs a text input' do
      expect(result).to have_element(:input, type: 'text', class: 'usa-input', name: 'object[first_name]')
      expect(result).not_to have_css('.usa-form-group--error')
      expect(result).not_to have_css('.usa-error-message')
    end

    it 'outputs a label' do
      expect(result).to have_element(:label, class: 'usa-label', for: 'object_first_name')
    end

    context 'with id option' do
      let(:result) { builder.text_field(:first_name, id: 'custom-id') }

      it 'outputs a label associated with the input with the custom id' do
        expect(result).to have_element(:input, id: 'custom-id')
        expect(result).to have_element(:label, for: 'custom-id')
      end
    end

    context 'with label option' do
      let(:result) { builder.text_field(:first_name, label: 'Custom label') }

      it 'outputs a label' do
        expect(result).to have_element(:label, text: 'Custom label', class: 'usa-label')
      end
    end

    context 'with hint' do
      let(:result) { builder.text_field(:first_name, hint: 'Enter your name') }

      it 'outputs a hint' do
        expect(result).to have_element(:div, text: 'Enter your name', class: 'usa-hint')
      end

      it 'adds aria-describedby to the input' do
        expect(result).to have_element(:input, aria_describedby: 'first_name_hint')
      end
    end

    context 'with errors' do
      let(:result) { builder.text_field(:first_name) }

      before do
        object.errors.add(:first_name, 'is invalid')
      end

      it 'outputs an error message' do
        expect(result).to have_element(:div, class: 'usa-form-group--error')
        expect(result).to have_element(:span, text: 'is invalid', class: 'usa-error-message')
      end
    end

    context 'with width' do
      let(:result) { builder.text_field(:first_name, width: 'md') }

      it 'adds a width class' do
        expect(result).to have_element(:input, class: 'usa-input usa-input--md')
      end
    end

    context 'with optional set to true' do
      let(:result) { builder.text_field(:first_name, label: 'Name', optional: true) }

      it 'outputs an optional label' do
        expect(result).to have_element(:label, text: 'Name (optional)')
      end
    end

    context 'with custom class' do
      let(:result) { builder.text_field(:first_name, class: 'custom-class') }

      it 'adds the class to the input' do
        expect(result).to have_element(:input, class: 'custom-class usa-input')
      end
    end

    context 'with label_class' do
      let(:result) { builder.text_field(:first_name, label_class: 'custom-label-class') }

      it 'adds the class to the label' do
        expect(result).to have_element(:label, class: 'usa-label custom-label-class')
      end
    end
  end

  describe '#hint' do
    let(:result) { builder.hint('Enter your name') }

    it 'outputs a hint' do
      expect(result).to have_element(:div, text: 'Enter your name', class: 'usa-hint')
    end
  end

  describe '#date_picker' do
    let(:result) { builder.date_picker(:start_date) }
    let(:object) { TestForm.new(start_date: Date.new(2024, 1, 31)) }

    it 'wraps the input with a date picker class' do
      expect(result).to have_element(:div, class: 'usa-date-picker usa-form-group')
    end

    it 'includes example format in the hint' do
      expect(result).to have_element(:p, text: "Format: mm/dd/yyyy")
    end

    it 'adds USWDS attributes for showing the current value' do
      expect(result).to have_element(:input, value: '01/31/2024')
      expect(result).to have_element(:div, class: 'usa-date-picker', "data-default-value": '2024-01-31')
    end

    context 'when no existing date value' do
      let(:object) { TestForm.new(start_date: nil) }

      it 'does not set a value' do
        expect(result).to have_element(:input, value: nil)
        expect(result).to have_element(:div, class: 'usa-date-picker', "data-default-value": nil)
      end
    end
  end

  describe '#fieldset' do
    let(:result) { builder.fieldset('Legend') { 'Fieldset content' } }

    it 'outputs a fieldset' do
      expect(result).to have_element(:fieldset, class: 'usa-fieldset')
    end

    it 'outputs a legend' do
      expect(result).to have_element(:legend, text: 'Legend', class: 'usa-legend')
    end

    it 'outputs the content within the block' do
      expect(result).to have_text('Fieldset content')
    end

    context 'with large_legend set to true' do
      let(:result) { builder.fieldset('Legend', large_legend: true) { 'Fieldset content' } }

      it 'outputs a large legend' do
        expect(result).to have_element(:legend, class: 'usa-legend margin-top-0 usa-legend--large')
      end
    end

    context 'with a hint provided' do
      let(:result) { builder.fieldset('Legend', hint: "Fieldset hint") { 'Fieldset content' } }

      it 'outputs a hint' do
        expect(result).to have_element(:div, class: 'usa-hint')
      end
    end

    context 'with a fieldset attribute error' do
      let(:result) { builder.fieldset('Legend', attribute: "first_name") { 'Fieldset content' } }

      before do
        object.errors.add(:first_name, 'is invalid')
      end

      it 'outputs an error message' do
        expect(result).to have_element(:div, class: 'usa-form-group--error')
        expect(result).to have_element(:span, text: 'is invalid', class: 'usa-error-message')
      end
    end
  end

  describe '#select' do
    let(:result) { builder.select(:first_name, [ 'Option 1', 'Option 2' ]) }

    it 'outputs a select field' do
      expect(result).to have_element(:select, class: 'usa-select', name: 'object[first_name]')
    end

    context 'with label' do
      let(:result) { builder.select(:first_name, [ 'Option 1', 'Option 2' ], label: 'Custom label') }

      it 'outputs a label' do
        expect(result).to have_element(:label, text: 'Custom label', class: 'usa-label')
      end
    end

    context 'with an error' do
      let(:result) { builder.select(:first_name, [ 'Option 1', 'Option 2' ]) }

      before do
        object.errors.add(:first_name, 'is invalid')
      end

      it 'outputs an error message' do
        expect(result).to have_element(:select, class: 'usa-select usa-input--error')
        expect(result).to have_element(:span, text: 'is invalid', class: 'usa-error-message')
      end
    end
  end

  describe '#submit' do
    let (:result) { builder.submit() }

    it 'outputs a submit button' do
      expect(result).to have_element(:input, type: 'submit', class: 'usa-button')
    end

    context 'with big set to true' do
      let (:result) { builder.submit(nil, { big: true }) }

      it 'outputs a big submit button' do
        expect(result).to have_element(:input, type: 'submit', class: 'usa-button--big')
      end
    end
  end

  describe '#check_box' do
    let(:result) { builder.check_box(:first_name) }

    it 'outputs a check box' do
      expect(result).to have_element(:div, class: 'usa-checkbox')
      expect(result).to have_element(:input, type: 'checkbox', class: 'usa-checkbox__input', name: 'object[first_name]')
    end

    context 'with hint' do
      let(:result) { builder.check_box(:first_name, hint: 'Check this box') }

      it 'outputs a hint' do
        expect(result).to have_element(:span, text: 'Check this box', class: 'usa-checkbox__label-description')
      end
    end

    context 'with multi-value checkboxes' do
      let(:result) { builder.check_box(:first_name, { label: "123" }, "val_123") }

      it 'sets a unique "for" value for the label' do
        expect(result).to have_element(:label, text: '123', for: 'object_first_name_val_123')
      end
    end
  end

  describe '#radio_button' do
    let(:result) { builder.radio_button(:first_name, 'yes') }

    it 'outputs a radio button' do
      expect(result).to have_element(:div, class: 'usa-radio')
      expect(result).to have_element(:input, type: 'radio', class: 'usa-radio__input', name: 'object[first_name]', value: 'yes')
    end

    it 'defaults to tile style' do
      expect(result).to have_element(:input, type: 'radio', class: 'usa-radio__input--tile')
    end

    context 'with hint' do
      let(:result) { builder.radio_button(:first_name, 'yes', hint: 'Select yes') }

      it 'outputs a hint' do
        expect(result).to have_element(:span, text: 'Select yes', class: 'usa-radio__label-description')
      end
    end

    context 'with tile option false' do
      let(:result) { builder.radio_button(:first_name, 'yes', tile: false) }

      it 'outputs a radio button without the tile class' do
        expect(result).to have_element(:input, type: 'radio', class: 'usa-radio__input')
        expect(result).not_to have_element(:input, type: 'radio', class: 'usa-radio__input--tile')
      end
    end
  end

  describe '#tax_id_field' do
    let(:result) { builder.tax_id_field(:first_name) }

    it 'outputs a text input' do
      expect(result).to have_element(:input, type: 'text', class: 'usa-input', name: 'object[first_name]')
      expect(result).not_to have_css('.usa-form-group--error')
      expect(result).not_to have_css('.usa-error-message')
    end

    it 'outputs a label' do
      expect(result).to have_element(:label, class: 'usa-label', for: 'object_first_name')
    end

    it 'includes an example in the hint' do
      expect(result).to have_element(:p, text: "For example, 123456789")
    end
  end

  describe '#yes_no' do
    let(:result) { builder.yes_no(:first_name, legend: 'Custom legend') }

    it 'outputs radio buttons for yes and no' do
      expect(result).to have_element(:input, type: 'radio', class: 'usa-radio__input', value: 'true', name: 'object[first_name]')
      expect(result).to have_element(:input, type: 'radio', class: 'usa-radio__input', value: 'false', name: 'object[first_name]')

      expect(result).to have_element(:label, text: 'Yes', class: 'usa-radio__label')
      expect(result).to have_element(:label, text: 'No', class: 'usa-radio__label')

      expect(result).to have_element(:legend, text: 'Custom legend', class: 'usa-legend')
    end

    context 'with custom labels' do
      let(:result) { builder.yes_no(:first_name,
        yes_options: { label: "Yes, I've taken leave before" },
        no_options: { label: "No, I haven't taken leave before" }
      ) }

      it 'outputs radio buttons with custom labels' do
        expect(result).to have_element(:label, text: "Yes, I've taken leave before")
        expect(result).to have_element(:label, text: "No, I haven't taken leave before")
      end
    end
  end

  describe '#memorable_date' do
    let(:object) { TestRecord.new }
    let(:result) { builder.memorable_date(:date_of_birth) }

    it 'includes a month select with all months' do
      expect(result).to have_element(:select, name: 'object[date_of_birth][month]')
      Date::MONTHNAMES.compact.each do |month_name|
        expect(result).to have_element(:option, text: month_name)
      end
    end

    it 'includes day and year number inputs' do
      expect(result).to have_element(:input, name: 'object[date_of_birth][day]')
      expect(result).to have_element(:input, name: 'object[date_of_birth][year]')
    end

    context 'with an existing date value' do
      let(:object) { TestRecord.new(date_of_birth: Date.new(2024, 3, 15)) }

      it 'pre-fills the month, day, and year fields' do
        expect(result).to have_element(:select) do |select|
          expect(select).to have_element(:option, text: 'March', selected: true)
        end
        expect(result).to have_element(:input, name: 'object[date_of_birth][day]', value: '15')
        expect(result).to have_element(:input, name: 'object[date_of_birth][year]', value: '2024')
      end
    end

    context 'with raw values' do
      before do
        allow(object).to receive(:date_of_birth_before_type_cast).and_return({ month: '3', day: '44', year: '2024' })
      end

      it 'pre-fills the month, day, and year fields from raw values' do
        expect(result).to have_element(:select) do |select|
          expect(select).to have_element(:option, value: '3', selected: true)
        end
        expect(result).to have_element(:input, name: 'object[date_of_birth][day]', value: '44')
        expect(result).to have_element(:input, name: 'object[date_of_birth][year]', value: '2024')
      end
    end

    context 'with custom legend and hint' do
      let(:result) { builder.memorable_date(:date_of_birth, legend: 'Custom Date', hint: 'Custom hint text') }

      it 'displays the custom legend and hint' do
        expect(result).to have_element(:legend, text: 'Custom Date', class: 'usa-legend')
        expect(result).to have_element(:span, text: 'Custom hint text', class: 'usa-hint')
      end
    end

    context 'with errors' do
      before do
        object.errors.add(:date_of_birth, :invalid_date)
      end

      it 'displays the error message' do
        expect(result).to have_element(:span, text: 'Date of birth is an invalid date')
      end
    end
  end

  describe '#name' do
    let(:result) { builder.name(:name) }
    let(:object) { TestRecord.new }

    it 'includes first, middle, last, and suffix name fields' do
      expect(result).to have_element(:input, name: 'object[name_first]')
      expect(result).to have_element(:input, name: 'object[name_middle]')
      expect(result).to have_element(:input, name: 'object[name_last]')
      expect(result).to have_element(:input, name: 'object[name_suffix]')
    end

    it 'applies the usa-input--xl class to all input fields' do
      expect(result).to have_element(:input, name: 'object[name_first]', class: /usa-input--xl/)
      expect(result).to have_element(:input, name: 'object[name_middle]', class: /usa-input--xl/)
      expect(result).to have_element(:input, name: 'object[name_last]', class: /usa-input--xl/)
      expect(result).to have_element(:input, name: 'object[name_suffix]', class: /usa-input--xl/)
    end

    it 'marks the middle name and suffix as optional' do
      expect(result).to have_element(:label, text: /Middle name.*optional/i)
      expect(result).to have_element(:label, text: /Suffix.*optional/i)
    end

    it 'includes hints for first and last name' do
      expect(result).to have_element(:div, text: /For example, Jose, Darren, or Mai/, class: 'usa-hint')
      expect(result).to have_element(:div, text: /For example, Martinez Gonzalez, Gu, or Smith/, class: 'usa-hint')
    end

    it 'uses I18n for labels' do
      expect(result).to have_element(:label, text: /First or given name/)
      expect(result).to have_element(:label, text: /Middle name/)
      expect(result).to have_element(:label, text: /Last or family name/)
    end

    it 'adds appropriate autocomplete attributes to name fields' do
      expect(result).to have_element(:input, name: 'object[name_first]', autocomplete: 'given-name')
      expect(result).to have_element(:input, name: 'object[name_middle]', autocomplete: 'additional-name')
      expect(result).to have_element(:input, name: 'object[name_last]', autocomplete: 'family-name')
      expect(result).to have_element(:input, name: 'object[name_suffix]', autocomplete: 'honorific-suffix')
    end

    context 'with an existing name value' do
      let(:object) { TestRecord.new(name: Strata::Name.new(first: "John", middle: "Adams", last: "Doe", suffix: "Jr.")) }

      it 'pre-fills the name fields' do
        expect(result).to have_element(:input, name: 'object[name_first]', value: 'John')
        expect(result).to have_element(:input, name: 'object[name_middle]', value: 'Adams')
        expect(result).to have_element(:input, name: 'object[name_last]', value: 'Doe')
        expect(result).to have_element(:input, name: 'object[name_suffix]', value: 'Jr.')
      end
    end

    context 'with custom legend and hints' do
      let(:result) { builder.name(:name,
        legend: 'Custom Name Legend',
        first_hint: 'Custom first name hint',
        last_hint: 'Custom last name hint'
      ) }

      it 'displays the custom legend and hints' do
        expect(result).to have_element(:legend, text: 'Custom Name Legend', class: 'usa-legend')
        expect(result).to have_element(:div, text: 'Custom first name hint', class: 'usa-hint')
        expect(result).to have_element(:div, text: 'Custom last name hint', class: 'usa-hint')
      end
    end
  end

  describe '#address_fields' do
    let(:result) { builder.address_fields(:address) }
    let(:object) { TestRecord.new }

    it 'includes street, city, state, and zip code fields' do
      expect(result).to have_element(:input, name: 'object[address_street_line_1]')
      expect(result).to have_element(:input, name: 'object[address_street_line_2]')
      expect(result).to have_element(:input, name: 'object[address_city]')
      expect(result).to have_element(:select, name: 'object[address_state]')
      expect(result).to have_element(:input, name: 'object[address_zip_code]')
    end

    it 'marks street address line 2 as optional' do
      expect(result).to have_element(:label, text: /Street address line 2.*optional/i)
    end

    it 'includes proper autocomplete attributes' do
      # See https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/autocomplete
      expect(result).to have_element(:input, name: 'object[address_street_line_1]', autocomplete: 'address-line1')
      expect(result).to have_element(:input, name: 'object[address_street_line_2]', autocomplete: 'address-line2')
      expect(result).to have_element(:input, name: 'object[address_city]', autocomplete: 'address-level2')
      expect(result).to have_element(:select, name: 'object[address_state]', autocomplete: 'address-level1')
      expect(result).to have_element(:input, name: 'object[address_zip_code]', autocomplete: 'postal-code')
    end

    it 'includes all states, territoriesm, and military posts in state dropdown' do
      expect(result).to have_element(:select, name: 'object[address_state]') do |select|
        expect(select).to have_element(:option, text: 'California', value: 'CA')
        expect(select).to have_element(:option, text: 'New York', value: 'NY')
        expect(select).to have_element(:option, text: 'Puerto Rico', value: 'PR')
        expect(select).to have_element(:option, text: 'Armed Forces Pacific', value: 'AP')
      end
    end

    context 'with an existing address value' do
      let(:object) { TestRecord.new(address: Strata::Address.new(street_line_1: "123 Main St", street_line_2: "Apt 4B", city: "Anytown", state: "CA", zip_code: "12345")) }

      it 'pre-fills the address fields' do
        expect(result).to have_element(:input, name: 'object[address_street_line_1]', value: '123 Main St')
        expect(result).to have_element(:input, name: 'object[address_street_line_2]', value: 'Apt 4B')
        expect(result).to have_element(:input, name: 'object[address_city]', value: 'Anytown')
        expect(result).to have_element(:select, name: 'object[address_state]') do |select|
          expect(select).to have_element(:option, value: 'CA', selected: true)
        end
        expect(result).to have_element(:input, name: 'object[address_zip_code]', value: '12345')
      end
    end

    context 'with custom legend' do
      let(:result) { builder.address_fields(:address, legend: 'What is your address?') }

      it 'displays the custom legend' do
        expect(result).to have_element(:legend, text: 'What is your address?')
      end
    end
  end

  describe '#date_range' do
    let(:object) { TestRecord.new }
    let(:result) { builder.date_range(:period) }

    it 'outputs two text fields with start and end dates' do
      expect(result).to have_element(:input, name: 'object[period_start]')
      expect(result).to have_element(:input, name: 'object[period_end]')
    end

    context 'with existing date values' do
      let(:object) { TestRecord.new(period: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)) }

      it 'pre-fills the start and end date fields' do
        expect(result).to have_element(:input, name: 'object[period_start]', value: '01/01/2024')
        expect(result).to have_element(:input, name: 'object[period_end]', value: '12/31/2024')
      end
    end

    context 'with custom legend' do
      let(:result) { builder.date_range(:period, legend: 'Date range') }

      it 'displays custom legend' do
        expect(result).to have_element(:legend, text: 'Date range')
      end
    end

    context 'with errors' do
      let(:object) do
        record = TestRecord.new(period: Date.new(2024, 12, 31)..Date.new(2023, 1, 1))
        record.valid?
        record
      end

      it 'displays error messages for both fields' do
        expect(result).to have_element(:span, text: 'Period start date cannot be after end date')
      end
    end
  end

  describe '#money_field' do
    let(:object) { TestRecord.new }
    let(:result) { builder.money_field(:weekly_wage) }

    it 'outputs a label' do
      expect(result).to have_element(:label, class: 'usa-label', for: 'object_weekly_wage')
    end

    it 'wraps the input in a form group' do
      expect(result).to have_element(:div, class: 'usa-form-group')
    end

    context 'with no value' do
      let(:object) { TestRecord.new(weekly_wage: nil) }

      it 'renders an empty input field' do
        expect(result).to have_element(:input, name: 'object[weekly_wage]', value: nil)
      end
    end

    context 'with an existing Money value' do
      let(:object) { TestRecord.new(weekly_wage: Strata::Money.new(cents: 150050)) }

      it 'pre-fills the field with the dollar amount' do
        expect(result).to have_element(:input, name: 'object[weekly_wage]', value: '1500.5')
      end
    end

    context 'with validation errors' do
      before do
        object.errors.add(:weekly_wage, 'must be a positive number')
      end

      it 'displays the error message' do
        expect(result).to have_element(:span, text: 'Weekly wage must be a positive number', class: 'usa-error-message')
      end

      it 'adds error styling to the form group' do
        expect(result).to have_element(:div, class: 'usa-form-group--error')
      end

      it 'adds error styling to the input' do
        expect(result).to have_element(:input, class: /usa-input--error/)
      end
    end

    context 'with custom label' do
      let(:result) { builder.money_field(:weekly_wage, label: 'Custom Amount') }

      it 'displays the custom label' do
        expect(result).to have_element(:label, text: 'Custom Amount')
      end
    end

    context 'with custom hint' do
      let(:result) { builder.money_field(:weekly_wage, hint: 'Enter the amount in dollars') }

      it 'displays the custom hint' do
        expect(result).to have_element(:div, text: 'Enter the amount in dollars', class: 'usa-hint')
      end
    end

    context 'with custom class' do
      let(:result) { builder.money_field(:weekly_wage, class: 'custom-class') }

      it 'adds the custom class to the input' do
        expect(result).to have_element(:input, class: /custom-class/)
      end
    end

    context 'with custom placeholder' do
      let(:result) { builder.money_field(:weekly_wage, placeholder: '0.00') }

      it 'adds the placeholder to the input' do
        expect(result).to have_element(:input, placeholder: '0.00')
      end
    end

    context 'with custom inputmode' do
      let(:result) { builder.money_field(:weekly_wage, inputmode: 'numeric') }

      it 'uses the custom inputmode' do
        expect(result).to have_element(:input, inputmode: 'numeric')
      end
    end

    context 'with additional HTML options' do
      let(:result) { builder.money_field(:weekly_wage, data: { test: 'value' }, aria: { label: 'Amount' }) }

      it 'passes through HTML options to the input' do
        expect(result).to have_element(:input, 'data-test': 'value', 'aria-label': 'Amount')
      end
    end
  end
end
