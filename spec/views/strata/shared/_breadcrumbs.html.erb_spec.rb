# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "strata/shared/_breadcrumbs.html.erb", type: :view do
  before do
    render partial: "strata/shared/breadcrumbs", locals: { breadcrumbs: breadcrumbs }
  end

  context "with a single breadcrumb" do
    let(:breadcrumbs) { [ { text: "Dashboard" } ] }

    it "renders a single breadcrumb without a link" do
      expect(rendered).to have_selector('nav.usa-breadcrumb')
      expect(rendered).to have_selector('ol.usa-breadcrumb__list')
      expect(rendered).to have_selector('li.usa-breadcrumb__list-item.usa-current[aria-current="page"]')
      expect(rendered).to have_selector('span', text: "Dashboard")
      expect(rendered).not_to have_selector('a.usa-breadcrumb__link')
    end
  end

  context "with multiple breadcrumbs" do
    let(:breadcrumbs) {
      [
        { text: "Home", href: "/" },
        { text: "Cases", href: "/cases" },
        { text: "Case #12345" }
      ]
    }

    it "renders all breadcrumbs with proper structure" do
      expect(rendered).to have_selector('nav.usa-breadcrumb')
      expect(rendered).to have_selector('ol.usa-breadcrumb__list')
    end

    it "renders clickable links for all but the last breadcrumb" do
      expect(rendered).to have_selector('li.usa-breadcrumb__list-item a.usa-breadcrumb__link[href="/"]', text: "Home")
      expect(rendered).to have_selector('li.usa-breadcrumb__list-item a.usa-breadcrumb__link[href="/cases"]', text: "Cases")
    end

    it "renders the last breadcrumb as current page without a link" do
      expect(rendered).to have_selector('li.usa-breadcrumb__list-item.usa-current[aria-current="page"]')
      expect(rendered).to have_selector('li.usa-current span', text: "Case #12345")
      expect(rendered).not_to have_selector('li.usa-current a')
    end

    it "has proper accessibility attributes" do
      expect(rendered).to have_selector('nav[aria-label]')
      expect(rendered).to have_selector('li[aria-current="page"]')
    end
  end

  context "with empty breadcrumbs array" do
    let(:breadcrumbs) { [] }

    it "renders the nav and empty list without raising" do
      expect(rendered).to have_selector('ol.usa-breadcrumb__list')
      expect(rendered).not_to have_selector('li')
    end
  end

  context "with breadcrumbs using the legacy link: key" do
    let(:breadcrumbs) {
      [
        { text: "Home", link: "/" },
        { text: "Cases", link: "/cases" },
        { text: "Case #12345" }
      ]
    }

    it "still renders the URLs as clickable links" do
      expect(rendered).to have_selector('a.usa-breadcrumb__link[href="/"]', text: "Home")
      expect(rendered).to have_selector('a.usa-breadcrumb__link[href="/cases"]', text: "Cases")
    end

    it "marks the last item as the current page without a link" do
      expect(rendered).to have_selector('li.usa-current span', text: "Case #12345")
      expect(rendered).not_to have_selector('li.usa-current a')
    end
  end

  context "with breadcrumbs containing special characters" do
    let(:breadcrumbs) {
      [
        { text: "Home & Dashboard", href: "/" },
        { text: "Cases > Applications", href: "/cases" },
        { text: "Case #12345 (Active)" }
      ]
    }

    it "properly escapes special characters in text" do
      expect(rendered).to include("Home &amp; Dashboard")
      expect(rendered).to include("Cases &gt; Applications")
      expect(rendered).to include("Case #12345 (Active)")
    end
  end
end
