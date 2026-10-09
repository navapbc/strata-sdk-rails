# frozen_string_literal: true

Rails.application.routes.draw do
  root "home#index"

  mount Strata::Engine => "/"

  mount Lookbook::Engine, at: "/lookbook"

  resources :passport_application_forms, only: [ :index, :new, :show, :create, :edit, :update ]
  resources :user_facing_ids, only: [ :index ]

  resources :sample_application_forms, only: [ :index, :new, :show, :create ] do
    member do
      SampleFlow.pages.each do |page|
        get page.edit_pathname
        patch page.update_pathname
      end

      get :review
      patch :submit
    end
  end

  scope path: "/staff" do
    resources :passport_cases do
      collection do
        get :closed
      end

      member do
        get :application_details
        get :tasks
        get :documents
        get :history
        get :notes
      end
    end

    resources :tasks, only: [ :index, :show, :update ] do
      collection do
        post :pick_up_next_task
      end
    end

    resources :audit_logs, only: [ :index ]

    get "search", to: "staff#search"
  end

  get "staff", to: "staff#index"

  # Test routes for layout yield :head verification (test environment only)
  if Rails.env.test?
    get "layout_test/staff_layout_without_head"
    get "layout_test/staff_layout_with_head"
    get "layout_test/application_layout_without_head"
    get "layout_test/application_layout_with_head"
  end
end
