# frozen_string_literal: true

class SampleApplicationFormsController < ApplicationController
  include Strata::Flows::ApplicationFormController

  before_action :set_new_form, only: [ :new, :create ]
  before_action :set_form, except: [ :new, :create, :index ]
  flow SampleFlow

  def index
    @sample_application_forms = SampleApplicationForm.all
  end

  def new
  end

  def show
  end

  def create
    if @sample_application_form.save
      redirect_to @sample_application_form
    else
      flash.now[:errors] = @sample_application_form.errors.full_messages
      render :new, status: :unprocessable_content
    end
  end

  def review
  end

  def submit
    if @sample_application_form.submit_application
      redirect_to sample_application_form_path(@sample_application_form)
    elsif @sample_application_form.errors.full_messages
      flash.now[:errors] = @sample_application_form.errors.full_messages
      render :review, status: :unprocessable_content
    else
      raise StandardError.new("The application could not be submitted.")
    end
  end

  def flow_record
    @sample_application_form
  end

  private

  def set_new_form
    @sample_application_form = SampleApplicationForm.new
  end

  def set_form
    @sample_application_form = SampleApplicationForm.find(flow_record_id)
  end
end
