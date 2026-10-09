# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Strata::Flows::RoutingExtensions do
  describe "#mount_flow_routes (via SampleFlow on the dummy app)" do
    let(:routes) { Rails.application.routes.routes }

    def route_for(name)
      routes.find { |r| r.name == name }
    end

    it "generates member routes for top-level flow pages" do
      expect(route_for("edit_name_sample_application_form")).not_to be_nil
      expect(route_for("update_name_sample_application_form")).not_to be_nil
      expect(route_for("edit_employer_name_sample_application_form")).not_to be_nil
    end

    it "dispatches top-level page routes to the parent controller" do
      route = route_for("edit_name_sample_application_form")
      expect(route.defaults[:controller]).to eq("sample_application_forms")
      expect(route.defaults[:action]).to eq("edit_name")
    end

    it "generates nested member routes under the loop's association" do
      route = route_for("edit_prior_employer_business_name_sample_application_form_sample_employment_detail")
      expect(route).not_to be_nil
      expect(route.path.spec.to_s).to match(%r{/sample_application_forms/:sample_application_form_id/sample_employment_details/:id/edit_prior_employer_business_name})
    end

    it "dispatches loop page routes to the parent controller" do
      route = route_for("update_prior_employer_role_sample_application_form_sample_employment_detail")
      expect(route).not_to be_nil
      expect(route.defaults[:controller]).to eq("sample_application_forms")
      expect(route.defaults[:action]).to eq("update_prior_employer_role")
    end

    it "leaves pre-existing member routes (review, submit) intact" do
      expect(route_for("review_sample_application_form")).not_to be_nil
      expect(route_for("submit_sample_application_form")).not_to be_nil
    end
  end

  describe "when called outside a resources block" do
    it "raises with a clear message" do
      expect {
        Rails.application.routes.draw do
          mount_flow_routes SampleFlow
        end
      }.to raise_error(ArgumentError, /resources block/)
    ensure
      Rails.application.reload_routes!
    end
  end
end
