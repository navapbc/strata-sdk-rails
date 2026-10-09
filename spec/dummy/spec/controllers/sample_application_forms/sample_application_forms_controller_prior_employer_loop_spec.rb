# frozen_string_literal: true

require 'rails_helper'

# Exercises the loop-aware behaviors of ApplicationFormController.
#
# Fixtures introduced by this feature (created in the impl phase):
#   - SampleEmploymentDetail model with :business_name and :role columns
#   - has_many :sample_employment_details on SampleApplicationForm
#   - A loop in SampleFlow over :sample_employment_details, named :prior_employer
#   - Nested routes under sample_application_forms for the loop pages
RSpec.describe SampleApplicationFormsController do
  render_views

  let(:application) { create(:sample_application_form, :submittable) }
  let!(:child_a) { create(:sample_employment_detail, sample_application_form: application, business_name: "Acme", role: "Engineer") }
  let!(:child_b) { create(:sample_employment_detail, sample_application_form: application, business_name: nil, role: nil) }

  describe "GET #edit_prior_employer_business_name" do
    it "renders for a specific child record" do
      get :edit_prior_employer_business_name, params: {
        sample_application_form_id: application.id,
        id: child_b.id,
        locale: "en"
      }

      expect(response).to have_http_status(:ok)
      # Form should reference the child, not the parent
      expect(response.body).to include(child_b.id.to_s)
    end
  end

  describe "PATCH #update_prior_employer_business_name" do
    context "with valid params" do
      it "updates only the targeted child record and leaves siblings unchanged" do
        original_child_a_business_name = child_a.business_name

        patch :update_prior_employer_business_name, params: {
          sample_application_form_id: application.id,
          id: child_b.id,
          sample_employment_detail: { business_name: "Globex" },
          locale: "en"
        }

        expect(child_a.reload.business_name).to eq(original_child_a_business_name)
        expect(child_b.reload.business_name).to eq("Globex")
      end

      it "redirects to the next loop page for the same child record (not last loop page)" do
        patch :update_prior_employer_business_name, params: {
          sample_application_form_id: application.id,
          id: child_b.id,
          sample_employment_detail: { business_name: "Globex" },
          locale: "en"
        }

        expect(response).to redirect_to(
          edit_prior_employer_role_sample_application_form_sample_employment_detail_path(application, child_b)
        )
      end
    end

    context "with invalid params" do
      it "re-renders the edit page with errors and does not change the record" do
        patch :update_prior_employer_business_name, params: {
          sample_application_form_id: application.id,
          id: child_b.id,
          sample_employment_detail: { business_name: "" },
          locale: "en"
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(child_b.reload.business_name).to be_nil
      end

      it "preserves submitted values on the re-rendered form rather than reverting to the DB state" do
        # child_a starts with business_name: "Acme". Submit an invalid value that
        # passes type coercion but fails validation, then verify the form shows
        # the submitted value (not the original "Acme").
        patch :update_prior_employer_business_name, params: {
          sample_application_form_id: application.id,
          id: child_a.id,
          sample_employment_detail: { business_name: "" },
          locale: "en"
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to have_field("sample_employment_detail[business_name]", with: "")
        expect(response.body).not_to have_field("sample_employment_detail[business_name]", with: "Acme")
      end
    end
  end

  describe "PATCH #update_prior_employer_role" do
    context "when on the last loop page for a non-last child" do
      it "redirects to the first loop page for the next child record" do
        patch :update_prior_employer_role, params: {
          sample_application_form_id: application.id,
          id: child_a.id,
          sample_employment_detail: { role: "Senior Engineer" },
          locale: "en"
        }

        expect(response).to redirect_to(
          edit_prior_employer_business_name_sample_application_form_sample_employment_detail_path(application, child_b)
        )
      end
    end

    context "when on the last loop page for the last child" do
      before do
        child_b.update!(business_name: "Globex")
      end

      it "exits the loop to the next top-level page" do
        patch :update_prior_employer_role, params: {
          sample_application_form_id: application.id,
          id: child_b.id,
          sample_employment_detail: { role: "Manager" },
          locale: "en"
        }

        expect(response.location).not_to match(/prior_employer/)
      end
    end
  end

  describe "loop with empty relation" do
    it "skips the loop on next_path from the page before it" do
      application.sample_employment_details.destroy_all

      patch :update_employer_name, params: {
        id: application.id,
        sample_application_form: { employer_name: "Initech" },
        locale: "en"
      }

      # next_path should not land on a prior_employer route since there are no children
      expect(response.location).not_to match(/prior_employer/)
    end
  end
end
