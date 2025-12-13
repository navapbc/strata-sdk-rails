# frozen_string_literal: true

Rails.application.routes.draw do
  mount Strata::Engine => "/"

  mount Lookbook::Engine, at: "/lookbook"

  resources :passport_application_forms, only: [ :index, :new, :show, :create ]

  resources "paid_leave_applications" do
    member do
      PaidLeaveFlow.pages.each do |page|
        get page.edit_pathname
        get page.update_pathname
      end
      get :review
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

    get "search", to: "staff#search"
  end

  get "staff", to: "staff#index"
end
