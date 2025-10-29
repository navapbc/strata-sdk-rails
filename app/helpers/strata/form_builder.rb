# frozen_string_literal: true

module Strata
  # FormBuilder is a custom form builder that provides USWDS-styled form components.
  # Beyond adding USWDS classes, this also supports setting the label, hint, and error
  # messages by just using the field helpers (i.e text_field, check_box), and adds
  # additional helpers like fieldset and hint.
  #
  # @see https://api.rubyonrails.org/classes/ActionView/Helpers/FormBuilder.html
  # @see https://designsystem.digital.gov/components/form-controls/
  #
  # @example Basic usage
  #   <%= strata_form_with(model: @user) do |f| %>
  #     <%= f.text_field :name, label: "Full Name", hint: "Enter your legal name" %>
  #     <%= f.email_field :email, label: "Email Address" %>
  #     <%= f.submit "Save" %>
  #   <% end %>
  #
  class FormBuilder < ActionView::Helpers::FormBuilder
    standard_helpers = %i[email_field file_field password_field text_area text_field]

    # Initializes a new FormBuilder instance and sets up the form with USWDS classes.
    #
    # @param args [Array] Arguments passed to the parent FormBuilder constructor
    def initialize(*args)
      super
      self.options[:html] ||= {}
      self.options[:html][:class] ||= "usa-form usa-form--large"
    end

    ########################################
    # Override standard helpers
    ########################################

    # Override default text fields to automatically include the label,
    # hint, and error elements
    #
    # Example usage:
    #   <%= f.text_field :foobar, { label: "Custom label text", hint: "Some hint text" } %>
    standard_helpers.each do |field_type|
      define_method(field_type) do |attribute, options = {}|
        classes = us_class_for_field_type(field_type, options[:width])
        classes += " usa-input--error" if has_error?(attribute)
        append_to_option(options, :class, " #{classes}")

        label_text = options.delete(:label)
        label_class = options.delete(:label_class) || ""
        skip_form_group = options.delete(:skip_form_group)

        label_options = options.except(:width, :class, :id).merge({
          class: label_class,
          for: options[:id]
        })
        field_options = options.except(:label, :hint, :label_class)

        if options[:hint]
          field_options[:aria_describedby] = hint_id(attribute)
        end

        content = us_text_field_label(attribute, label_text, label_options) +
          super(attribute, field_options)

        if skip_form_group
          return content
        end

        form_group(attribute, options[:group_options] || {}) do
          content
        end
      end
    end

    # Renders a checkbox field with USWDS styling.
    #
    # @param [Symbol] attribute The attribute name
    # @param [Hash] options Options for the checkbox
    # @param args [Array] Additional arguments for the standard checkbox helper
    # @option options [String] :label Custom label text
    # @return [String] The rendered HTML for the checkbox
    def check_box(attribute, options = {}, *args)
      append_to_option(options, :class, " #{us_class_for_field_type(:check_box)}")

      label_text = options.delete(:label)

      @template.content_tag(:div, class: "usa-checkbox") do
        super(attribute, options, *args) + us_toggle_label("checkbox", attribute, label_text, options)
      end
    end

    def radio_button(attribute, tag_value, options = {})
      append_to_option(options, :class, " #{us_class_for_field_type(:radio_button)}")

      label_text = options.delete(:label)
      label_options = { for: field_id(attribute, tag_value) }.merge(options)

      tile = options.key?(:tile) ? options.delete(:tile) : true
      append_to_option(options, :class, " usa-radio__input--tile") if tile

      @template.content_tag(:div, class: "usa-radio") do
        super(attribute, tag_value, options) + us_toggle_label("radio", attribute, label_text, label_options)
      end
    end

    def select(attribute, choices, options = {}, html_options = {})
      append_to_option(html_options, :class, " usa-select")

      label_text = options.delete(:label)
      skip_form_group = options.delete(:skip_form_group)

      content = us_text_field_label(attribute, label_text, options) +
        super(attribute, choices, options, html_options)

      if skip_form_group
        return content
      end

      form_group(attribute) { content }
    end

    def submit(value = nil, options = {})
      append_to_option(options, :class, " usa-button")

      if options[:big]
        append_to_option(options, :class, " usa-button--big margin-y-6")
      end

      super(value, options)
    end

    def honeypot_field
      spam_trap_classes = "opacity-0 position-absolute z-bottom top-0 left-0 height-0 width-0"
      label_text = "Do not fill in this field. It is an anti-spam measure."

      @template.content_tag(:div, class: "usa-form-group #{spam_trap_classes}") do
        label(:spam_trap, label_text, { tabindex: -1, class: "usa-label #{spam_trap_classes}" }) +
        @template.text_field(@object_name, :spam_trap, { autocomplete: "false", tabindex: -1, class: "usa-input #{spam_trap_classes}" })
      end
    end

    ########################################
    # Custom helpers
    ########################################

    def tax_id_field(attribute, options = {})
      options[:inputmode] = "numeric"
      options[:placeholder] = "_________"
      options[:width] = "md"

      append_to_option(options, :class, " usa-masked")
      append_to_option(options, :hint, @template.content_tag(:p, I18n.t("strata.form_builder.tax_id_format")))

      text_field(attribute, options)
    end

    def date_picker(attribute, options = {})
      if object
        raw_value = object.send(attribute)
        if raw_value.nil? && object.respond_to?("#{attribute}_before_type_cast")
          raw_value = object.send("#{attribute}_before_type_cast")
        end
      end

      append_to_option(options, :hint, @template.content_tag(:p, I18n.t("strata.form_builder.date_picker_format")))

      group_options = options[:group_options] || {}
      append_to_option(group_options, :class, " usa-date-picker")

      if raw_value.is_a?(Date)
        append_to_option(group_options, :"data-default-value", raw_value.strftime("%Y-%m-%d"))
        value = raw_value.strftime("%m/%d/%Y") if raw_value.is_a?(Date)
      else
        value = raw_value
      end

      text_field(attribute, options.merge(value: value, group_options: group_options))
    end

    # Renders a memorable date input with month, day, and year fields.
    #
    # @param [Symbol] attribute The attribute name
    # @param [Hash] options Options for the memorable date
    # @option options [String] :legend Custom legend text
    # @option options [String] :hint Custom hint text
    # @return [String] The rendered HTML for the memorable date input
    # @see https://designsystem.digital.gov/components/memorable-date/
    def memorable_date(attribute, options = {})
      legend_text = options.delete(:legend) || human_name(attribute)
      hint_text = options.delete(:hint) || I18n.t("strata.form_builder.memorable_date_hint")
      hint_id = "#{attribute}_hint"

      object_value = object&.send(attribute)
      raw_value = object&.send("#{attribute}_before_type_cast") || {}
      month_value = object_value&.month || raw_value[:month] || nil
      day_value = object_value&.day || raw_value[:day] || nil
      year_value = object_value&.year || raw_value[:year] || nil

      month_options = (1..12).map do |m|
        [ Date::MONTHNAMES[m], m ]
      end
      month_options.unshift([ I18n.t("strata.form_builder.select_month"), "" ])

      fieldset(legend_text) do
        @template.content_tag(:span, hint_text, class: "usa-hint", id: hint_id) +
        field_error(attribute) +
        @template.content_tag(:div, class: "usa-memorable-date") do
          fields_for attribute do |date_of_birth_fields|
            # Month select
            @template.content_tag(:div, class: "usa-form-group usa-form-group--month usa-form-group--select") do
              date_of_birth_fields.select(
                "month",
                month_options,
                { label: "Month", skip_form_group: true, selected: month_value },
                {
                  class: "usa-select",
                  "aria-describedby": hint_id
                }
              )
            end +

            # Day input
            @template.content_tag(:div, class: "usa-form-group usa-form-group--day") do
              date_of_birth_fields.text_field(
                "day",
                {
                  label: "Day",
                  skip_form_group: true,
                  type: "number",
                  value: day_value,
                  "aria-describedby": hint_id,
                  maxlength: 2,
                  pattern: "[0-9]*",
                  inputmode: "numeric"
                }
              )
            end +

            # Year input
            @template.content_tag(:div, class: "usa-form-group usa-form-group--year") do
              date_of_birth_fields.text_field(
                "year",
                {
                  label: "Year",
                  skip_form_group: true,
                  type: "number",
                  value: year_value,
                  "aria-describedby": hint_id,
                  minlength: 4,
                  maxlength: 4,
                  pattern: "[0-9]*",
                  inputmode: "numeric"
                }
              )
            end
          end
        end
      end
    end

    # Renders a name input with first, middle, and last name fields.
    #
    # @param [Symbol] attribute The attribute name
    # @param [Hash] options Options for the name input
    # @option options [String] :legend Custom legend text
    # @option options [String] :first_hint Custom hint text for first name
    # @option options [String] :last_hint Custom hint text for last name
    # @return [String] The rendered HTML for the name input
    def name(attribute, options = {})
      legend_text = options.delete(:legend) || I18n.t("strata.form_builder.name.legend")
      first_hint_text = options.delete(:first_hint) || I18n.t("strata.form_builder.name.first_hint")
      last_hint_text = options.delete(:last_hint) || I18n.t("strata.form_builder.name.last_hint")
      first_hint_id = "#{attribute}_first_hint"
      last_hint_id = "#{attribute}_last_hint"

      fieldset(legend_text) do
        @template.content_tag(:div) do
          # We need to pass builder: self.class only for testing purposes, but it shouldn't harm
          # anything in production. This is because in the test context fields_for
          # cannot infer the custom form builder class from the view context.

          # First name field
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_first",
              label: I18n.t("strata.form_builder.name.first_label"),
              hint: first_hint_text,
              class: "usa-input usa-input--xl",
              "aria-describedby": first_hint_id,
              autocomplete: "given-name"
            )
          end +

          # Middle name field (optional)
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_middle",
              label: I18n.t("strata.form_builder.name.middle_label"),
              class: "usa-input usa-input--xl",
              optional: true,
              autocomplete: "additional-name"
            )
          end +

          # Last name field
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_last",
              label: I18n.t("strata.form_builder.name.last_label"),
              hint: last_hint_text,
              class: "usa-input usa-input--xl",
              autocomplete: "family-name"
            )
          end +

          # Suffix field (optional)
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_suffix",
              label: I18n.t("strata.form_builder.name.suffix_label"),
              class: "usa-input usa-input--xl",
              optional: true,
              autocomplete: "honorific-suffix"
            )
          end
        end
      end
    end

    def field_error(attribute)
      return "".html_safe unless has_error?(attribute)

      @template.content_tag(:span, object.errors.full_messages_for(attribute).first, class: "usa-error-message")
    end

    def fieldset(legend, options = {}, &block)
      legend_classes = "usa-legend"

      if options[:large_legend]
        legend_classes += " usa-legend--large"
      end

      form_group(options[:attribute]) do
        @template.content_tag(:fieldset, class: "usa-fieldset") do
          @template.content_tag(:legend, legend, class: legend_classes) + @template.capture(&block)
        end
      end
    end

    # Check if a field has a validation error
    def has_error?(attribute)
      return unless object
      object.errors.has_key?(attribute)
    end

    def human_name(attribute)
      return unless object
      object.class.human_attribute_name(attribute)
    end

    def hint(text)
      @template.content_tag(:div, @template.raw(text), class: "usa-hint")
    end

    def form_group(attribute = nil, options = {}, &block)
      append_to_option(options, :class, " usa-form-group")
      children = @template.capture(&block)

      if options[:show_error] or (attribute and has_error?(attribute))
        append_to_option(options, :class, " usa-form-group--error")
      end

      @template.content_tag(:div, children, options)
    end

    def yes_no(attribute, options = {})
      yes_options = options[:yes_options] || {}
      no_options = options[:no_options] || {}
      value = if object then object.send(attribute) else nil end

      yes_options = { label: I18n.t("strata.form_builder.boolean_true") }.merge(yes_options)
      no_options = { label: I18n.t("strata.form_builder.boolean_false") }.merge(no_options)

      @template.capture do
        # Hidden field included for same reason as radio button collections (https://api.rubyonrails.org/classes/ActionView/Helpers/FormOptionsHelper.html#method-i-collection_radio_buttons)
        hidden_field(attribute, value: "") +
        fieldset(options[:legend] || human_name(attribute), { attribute: attribute }) do
          buttons =
            radio_button(attribute, true, yes_options) +
            radio_button(attribute, false, no_options)

          if has_error?(attribute)
            field_error(attribute) + buttons
          else
            buttons
          end
        end
      end
    end

    # Renders an address input with street, city, state, zip code fields.
    #
    # @param [Symbol] attribute The attribute name
    # @param [Hash] options Options for the address input
    # @option options [String] :legend Custom legend text
    # @return [String] The rendered HTML for the address input
    def address_fields(attribute, options = {})
      legend_text = options.delete(:legend) || I18n.t("strata.form_builder.address.legend")

      fieldset(legend_text) do
        @template.content_tag(:div) do
          # Street address line 1
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_street_line_1",
              label: I18n.t("strata.form_builder.address.street_line_1_label"),
              class: "usa-input usa-input--xl",
              autocomplete: "address-line1"
            )
          end +

          # Street address line 2 (optional)
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_street_line_2",
              label: I18n.t("strata.form_builder.address.street_line_2_label"),
              class: "usa-input usa-input--xl",
              optional: true,
              autocomplete: "address-line2"
            )
          end +

          # City (required)
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_city",
              label: I18n.t("strata.form_builder.address.city_label"),
              class: "usa-input usa-input--xl",
              autocomplete: "address-level2"
            )
          end +

          # State dropdown (required)
          @template.content_tag(:div, class: "usa-form-group") do
            select(
              "#{attribute}_state",
              us_states_and_territories,
              { label: I18n.t("strata.form_builder.address.state_label") },
              { class: "usa-select", autocomplete: "address-level1" }
            )
          end +

          # ZIP code
          @template.content_tag(:div, class: "usa-form-group") do
            text_field(
              "#{attribute}_zip_code",
              label: I18n.t("strata.form_builder.address.zip_code_label"),
              hint: I18n.t("strata.form_builder.address.zip_code_hint"),
              class: "usa-input usa-input--md",
              inputmode: "numeric",
              pattern: "[0-9]{5}(-[0-9]{4})?",
              autocomplete: "postal-code"
            )
          end
        end
      end
    end

    def date_range(attribute, options = {})
      legend_text = options.delete(:legend) || human_name(attribute)
      start_hint_text = I18n.t("strata.form_builder.date_range.start_hint")
      end_hint_text = I18n.t("strata.form_builder.date_range.end_hint")

      fieldset(legend_text) do
        field_error(attribute) +
        form_group do
          date_picker(
            "#{attribute}_start",
            hint: start_hint_text,
            label: I18n.t("strata.form_builder.date_range.start_label")
          )
        end +
        form_group do
          date_picker(
            "#{attribute}_end",
            hint: end_hint_text,
            label: I18n.t("strata.form_builder.date_range.end_label")
          )
        end
      end
    end

    # Renders a money input field for dollar amounts.
    #
    # @param [Symbol] attribute The attribute name
    # @param [Hash] options Options for the money field
    # @option options [String] :label Custom label text
    # @option options [String] :hint Custom hint text
    # @option options [String] :width Width class (e.g., 'md', 'lg')
    # @option options [String] :class Custom CSS classes
    # @option options [String] :placeholder Placeholder text
    # @option options [String] :inputmode Input mode (defaults to 'decimal')
    # @return [String] The rendered HTML for the money input
    def money_field(attribute, options = {})
      label_text = options.delete(:label) || human_name(attribute)
      hint_text = options.delete(:hint)
      width = options.delete(:width)
      custom_class = options.delete(:class)
      placeholder = options.delete(:placeholder)
      inputmode = options.delete(:inputmode) || "decimal"

      # Get the existing Money object value if present
      object_value = object&.send(attribute)
      dollar_value = object_value&.dollar_amount

      classes = us_class_for_field_type(:text_field, width)
      classes += " usa-input--error" if has_error?(attribute)
      classes += " #{custom_class}" if custom_class

      form_group(attribute, options[:group_options] || {}) do
        us_text_field_label(attribute, label_text, { hint: hint_text }) +
        fields_for(attribute) do |money_fields|
          money_fields.text_field(
            "dollar_amount",
            {
              skip_form_group: true,
              value: dollar_value,
              class: classes,
              inputmode: inputmode,
              placeholder: placeholder
            }.merge(options.except(:group_options))
          )
        end
      end
    end

    def us_states_and_territories
      [
        [ "", "" ],
        [ "AK - Alaska", "AK" ],
        [ "AL - Alabama", "AL" ],
        [ "AR - Arkansas", "AR" ],
        [ "AS - American Samoa", "AS" ],
        [ "AZ - Arizona", "AZ" ],
        [ "CA - California", "CA" ],
        [ "CO - Colorado", "CO" ],
        [ "CT - Connecticut", "CT" ],
        [ "DC - District of Columbia", "DC" ],
        [ "DE - Delaware", "DE" ],
        [ "FL - Florida", "FL" ],
        [ "GA - Georgia", "GA" ],
        [ "GU - Guam", "GU" ],
        [ "HI - Hawaii", "HI" ],
        [ "IA - Iowa", "IA" ],
        [ "ID - Idaho", "ID" ],
        [ "IL - Illinois", "IL" ],
        [ "IN - Indiana", "IN" ],
        [ "KS - Kansas", "KS" ],
        [ "KY - Kentucky", "KY" ],
        [ "LA - Louisiana", "LA" ],
        [ "MA - Massachusetts", "MA" ],
        [ "MD - Maryland", "MD" ],
        [ "ME - Maine", "ME" ],
        [ "MI - Michigan", "MI" ],
        [ "MN - Minnesota", "MN" ],
        [ "MO - Missouri", "MO" ],
        [ "MP - Northern Mariana Islands", "MP" ],
        [ "MS - Mississippi", "MS" ],
        [ "MT - Montana", "MT" ],
        [ "NC - North Carolina", "NC" ],
        [ "ND - North Dakota", "ND" ],
        [ "NE - Nebraska", "NE" ],
        [ "NH - New Hampshire", "NH" ],
        [ "NJ - New Jersey", "NJ" ],
        [ "NM - New Mexico", "NM" ],
        [ "NV - Nevada", "NV" ],
        [ "NY - New York", "NY" ],
        [ "OH - Ohio", "OH" ],
        [ "OK - Oklahoma", "OK" ],
        [ "OR - Oregon", "OR" ],
        [ "PA - Pennsylvania", "PA" ],
        [ "PR - Puerto Rico", "PR" ],
        [ "RI - Rhode Island", "RI" ],
        [ "SC - South Carolina", "SC" ],
        [ "SD - South Dakota", "SD" ],
        [ "TN - Tennessee", "TN" ],
        [ "TX - Texas", "TX" ],
        [ "UT - Utah", "UT" ],
        [ "VA - Virginia", "VA" ],
        [ "VI - U.S. Virgin Islands", "VI" ],
        [ "VT - Vermont", "VT" ],
        [ "WA - Washington", "WA" ],
        [ "WI - Wisconsin", "WI" ],
        [ "WV - West Virginia", "WV" ],
        [ "WY - Wyoming", "WY" ],
        [ "AA - Armed Forces Americas", "AA" ],
        [ "AE - Armed Forces Europe", "AE" ],
        [ "AP - Armed Forces Pacific", "AP" ]
      ]
    end

    private

    def append_to_option(options, key, value)
      current_value = options[key] || ""

      if current_value.is_a?(Proc)
        options[key] = -> { current_value.call + value }
      else
        options[key] = current_value + value
      end
    end

    def us_class_for_field_type(field_type, width = nil)
      case field_type
      when :check_box
        "usa-checkbox__input usa-checkbox__input--tile"
      when :file_field
        "usa-file-input"
      when :radio_button
        "usa-radio__input"
      when :text_area
        "usa-textarea"
      else
        classes = "usa-input"
        classes += " usa-input--#{width}" if width
        classes
      end
    end


    # Render the label, hint text, and error message for a form field
    def us_text_field_label(attribute, text = nil, options = {})
      hint_option = options.delete(:hint)
      classes = "usa-label"
      for_attr = options[:for] || field_id(attribute)

      if options[:class]
        classes += " #{options[:class]}"
      end

      unless text
        text = human_name(attribute)
      end

      if options[:optional]
        text += @template.content_tag(:span, " (#{I18n.t('strata.form_builder.optional').downcase})", class: "usa-hint")
      end

      if hint_option
        if hint_option.is_a?(Proc)
          hint_content = @template.capture(&hint_option)
        else
          hint_content = @template.raw(hint_option)
        end

        hint = @template.content_tag(:div, hint_content, id: hint_id(attribute), class: "usa-hint")
      end

      label(attribute, @template.raw(text), { class: classes, for: for_attr }) + field_error(attribute) + hint
    end

    # Label for a checkbox or radio
    def us_toggle_label(type, attribute, text = nil, options = {})
      hint_text = options.delete(:hint)
      label_text = text || object.class.human_attribute_name(attribute)
      options = options.merge({ class: "usa-#{type}__label" })

      if hint_text
        hint = @template.content_tag(:span, hint_text, class: "usa-#{type}__label-description")
        label_text = "#{label_text} #{hint}".html_safe
      end

      label(attribute, label_text, options)
    end

    def hint_id(attribute)
      "#{attribute}_hint"
    end
  end
end
