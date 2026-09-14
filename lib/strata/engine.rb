# frozen_string_literal: true

module Strata
  # Engine is the Rails engine for the Strata SDK.
  # It provides configuration for integrating Strata components into a Rails application.
  #
  # The engine handles namespace isolation, helper loading, preview path configuration,
  # and event manager cleanup during code reloading.
  #
  class Engine < ::Rails::Engine
    isolate_namespace Strata

    config.to_prepare do
      ActiveSupport.on_load :action_controller do
        helper Strata::ApplicationHelper
      end
    end

    config.generators do |g|
      g.test_framework :rspec
    end

    initializer "strata.previews" do |app|
      config.lookbook.preview_paths << Strata::Engine.root.join("app", "previews") if config.respond_to?(:lookbook)
    end

    initializer "strata.factory_bot", after: "factory_bot.set_factory_paths" do
      if defined?(FactoryBot)
        FactoryBot.definition_file_paths << File.expand_path("../../../spec/factories/strata", __FILE__)
      end
    end

    initializer "strata.inflections" do
      ActiveSupport::Inflector.inflections(:en) do |inflect|
        inflect.acronym "US"
        inflect.acronym "USA"
      end
    end

    initializer "strata.field_error_proc" do
      ActiveSupport.on_load(:action_view) do
        # Strata renders its own error markup (usa-input--error,
        # usa-form-group--error, usa-error-message) for every form helper, so
        # Rails' default field_with_errors wrapper is redundant on top of that
        # and breaks USWDS adjacent-sibling selectors (e.g. .usa-input-prefix
        # + input, input + .usa-input-suffix). Override at the engine level so
        # the wrapper never appears in Strata-rendered forms.
        #
        # A host that explicitly wants the wrapper back can set
        # ActionView::Base.field_error_proc = ActionView::Base::DEFAULT_FIELD_ERROR_PROC
        # in their own initializer after Strata's runs.
        #
        # See docs/decisions/field-error-proc-override.md (ADR-002).
        ActionView::Base.field_error_proc = ->(html_tag, _instance) { html_tag }
      end
    end

    initializer "strata.importmap", before: "importmap" do |app|
      if app.config.respond_to?(:importmap)
        app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      end
    end

    initializer "strata.assets" do |app|
      app.config.assets.paths << Engine.root.join("app/components")
      app.config.assets.precompile += Dir[Engine.root.join("app/components/strata/**/*.js")].map { |f| f.sub(%r{.*/app/components/}, "") }
    end

    config.after_initialize do
      Rails.autoloaders.main.on_unload("Strata::EventManager") do |klass|
        klass.unsubscribe_all
      end
    end
  end
end
