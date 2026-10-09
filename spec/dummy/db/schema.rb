# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_20_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "foo_test_cases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "status", default: 0
    t.string "business_process_current_step"
    t.uuid "application_form_id"
    t.jsonb "facts", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "passport_application_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name_first"
    t.string "name_last"
    t.date "date_of_birth"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "submitted_at"
    t.string "name_middle"
    t.string "name_suffix"
  end

  create_table "passport_cases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "passport_id", null: false
    t.string "business_process_current_step"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "application_form_id"
    t.jsonb "facts"
    t.index ["application_form_id"], name: "index_passport_cases_on_application_form_id"
  end

  create_table "sample_application_forms", force: :cascade do |t|
    t.uuid "user_id"
    t.integer "status"
    t.datetime "submitted_at"
    t.string "applicant_name_first"
    t.date "date_of_birth"
    t.string "employer_name"
    t.string "leave_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sample_employment_details", force: :cascade do |t|
    t.bigint "sample_application_form_id"
    t.string "business_name"
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sample_application_form_id"], name: "index_sample_employment_details_on_sample_application_form_id"
  end

  create_table "strata_audit_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "subject_id"
    t.string "subject_type"
    t.uuid "actor_id"
    t.string "actor_type"
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_strata_audit_lines_on_polymorphic_actor"
    t.index ["created_at"], name: "index_strata_audit_lines_on_created_at"
    t.index ["subject_type", "subject_id", "created_at"], name: "index_strata_audit_lines_on_subject_and_created_at", order: { created_at: :desc }
  end

  create_table "strata_determinations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "subject_id", null: false
    t.string "subject_type", null: false
    t.string "decision_method", null: false
    t.string "outcome", null: false
    t.jsonb "determination_data", default: {}, null: false
    t.uuid "determined_by_id"
    t.datetime "determined_at", null: false
    t.datetime "created_at", null: false
    t.string "reasons", default: [], null: false, array: true
    t.index ["created_at"], name: "index_strata_determinations_on_created_at"
    t.index ["determined_at"], name: "index_strata_determinations_on_determined_at"
    t.index ["determined_by_id"], name: "index_strata_determinations_on_determined_by_id"
    t.index ["subject_id", "subject_type"], name: "index_strata_determinations_on_polymorphic_subject"
  end

  create_table "strata_tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "type"
    t.text "description"
    t.integer "status", default: 0
    t.uuid "assignee_id"
    t.uuid "case_id"
    t.date "due_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "case_type"
    t.index ["assignee_id"], name: "index_strata_tasks_on_assignee_id"
    t.index ["case_id"], name: "index_strata_tasks_on_case_id"
    t.index ["status"], name: "index_strata_tasks_on_status"
    t.index ["type"], name: "index_strata_tasks_on_type"
  end

  create_table "test_application_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "status", default: 0
    t.string "test_string"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "submitted_at"
    t.uuid "user_id"
    t.string "applicant_name_first"
    t.string "applicant_name_middle"
    t.string "applicant_name_last"
    t.string "applicant_name_suffix"
    t.string "mailing_address_street_line_1"
    t.string "mailing_address_street_line_2"
    t.string "mailing_address_city"
    t.string "mailing_address_state"
    t.string "mailing_address_zip_code"
    t.date "date_of_birth"
    t.integer "salary"
    t.string "ssn"
    t.date "hire_date"
    t.integer "leave_type"
    t.boolean "reviewed"
    t.date "start_date"
    t.text "notes"
    t.integer "age"
    t.string "employer_name"
  end

  create_table "test_cases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "business_process_current_step"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "application_form_id"
    t.jsonb "facts"
    t.index ["application_form_id"], name: "index_test_cases_on_application_form_id"
  end

  create_table "test_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "date_of_birth"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name_first"
    t.string "name_middle"
    t.string "name_last"
    t.string "address_street_line_1"
    t.string "address_street_line_2"
    t.string "address_city"
    t.string "address_state"
    t.string "address_zip_code"
    t.string "tax_id"
    t.date "period_start"
    t.date "period_end"
    t.integer "weekly_wage"
    t.jsonb "addresses"
    t.jsonb "leave_periods"
    t.jsonb "names"
    t.jsonb "reporting_periods"
    t.date "adopted_on"
    t.jsonb "activity_reporting_periods"
    t.string "reporting_period"
    t.string "activity_reporting_period"
    t.string "base_period_start"
    t.string "base_period_end"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "sample_employment_details", "sample_application_forms"
  add_foreign_key "strata_tasks", "users", column: "assignee_id", on_delete: :nullify
end
