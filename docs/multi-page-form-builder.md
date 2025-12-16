# Multi-Page Form Builder

The Multi-Page Form Builder enables developers to create complex forms that span multiple pages using field-tested design patterns from government applications. It provides a DSL for defining forms that follow best practices for accessibility, user experience, and data collection.

> [!NOTE]  
> The Strata Rules Engine is still a work in progress, and detailed documentation will be provided as the feature matures.

## Key Features

- **Easy to define and read**—Form flows are designed to be readable and maintainable, allowing developers to easily see how all the pages on the form are organized.
- **Automatically defined routes and controller actions**—Routes and controller actions for each of the form's pages are automatically generated.
- **Built-in views**—Prebuilt views that show the current page, current task/section, and overall progress of the form.
- **Customizable**—Routes, controller actions, and views are all customizable if the default behavior does not meet the application's needs.
- **[FUTURE] Supports looping pattern**—Supports gathering information about multiple people or items in a single or multi-page loop.

## Design Principles

### Limit questions to one per page, where possible

The form builder encourages a one-question-per-page approach.Through usability testing and secondary research, we’ve learned that taking a one-question-per-page approach increases people’s comfort and confidence and reduces their cognitive burden while moving through an application.

This approach is not a strict rule. In some cases, it might be a better user experience to pair some questions on the same page together, e.g., name and birth date.

### Break up large application forms into a task list

A task list page is used to introduce the application and show what's needed to complete it. As a user works on each "task", the task list page updates to reflect their progress through the application.

A task might include:

- Answering a group of related questions
- Uploading documents
- Entering payment information

With the task list page, a user can review key details about the upcoming task so they know what to expect. Users can start, stop, and resume their progress in the application.

### Looping pattern for collecting information about multiple entities

When needing to collect a large amount of information about a person, or about multiple people, these questions may be asked in a loop.

There are 2 types of loops:

- Multi-page loops: information about one person spans multiple pages. Use this when there’s a lot of information to collect about someone that would be better broken up over multiple pages, and multiple people’s information would be gathered. For example, adding household members is a good use case for a multi-page loop since name, contact information, DOB, address etc. need to be collected for each person added.
- Single page loops: information about one person takes one full page. Use this when all the questions about one person in a series of people can be asked in one page without being too overwhelming for applicants.

## Implementing a multi-page form

### Defining an ApplicationFormFlow

Multi-page forms are based on a flow definition; define a form flow by using the custom DSL provided.

```ruby
class LeaveApplicationFormFlow
  include Strata::Flows::ApplicationFormFlow

  task :personal_information do
    question_page :name
    question_page :date_of_birth
    question_page :tax_identifier
  end

  task :leave_details do
    question_page :leave_type
    question_page :leave_dates
  end
end
```

A task describes an ordered series of questions, and can be represented as a section within a task list if the flow contains multiple tasks.

By default, a question page is assumed to have a single field with the same name. For pages with multiple fields, define them as follows:

```ruby
question_page :name, fields: [
    :applicant_name_first,
    :applicant_name_middle,
    :applicant_name_last,
    :applicant_name_suffix,
]
```

If you are accepting nested attributes for your model, ensure that the fields are formatted to pass into `#assign_attributes`:

```ruby
question_page :employment_details, fields: [
    employment_details_attributes: [
        :id,
        :employer_name,
        :employer_fein
    ]
]
```

### Generating Routes

Routes can be generated for your application form's controller:

```ruby
class LeaveApplicationFormsController
    include Flows::ApplicationFormController

    # Generate edit/update actions for each of the question pages in your flow
    flow Flows::LeaveApplicationFormFlow

    # (Optional) Define a custom layout for generated form routes
    layout "leave_application_form", only: Flows::LeaveApplicationFormFlow.generated_routes

    def flow_record
      # In most scenarios, you'll likely have a before_action that sets this, e.g.
      # @leave_application_form ||= authorize(LeaveApplication.find(params[:id]), :update?)
      @leave_application
    end
  end
```

In your `routes.rb` file, use your flow class to define the routes:

```ruby
resources "leave_application_forms" do
    member do
      LeaveApplicationFormFlow.pages.each do |page|
        get page.edit_pathname
        get page.update_pathname
      end
    end
end
```

### Adding Views

Default views are currently not auto-generated. You must add views for every question page in order for them to render correctly.

For a given question page, you will need to add an `edit_*.html.erb` file that renders the form. For example:

```
app/views/leave_application_forms/edit_name.html.erb
app/views/leave_application_forms/edit_date_of_birth.html.erb
...
```

Strata provides each controller action with the following instance variables for use within your layouts and templates:

| Name         | Class                                                                    | Description                                                                                                                                                  |
| ------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `@flow`      | [ApplicationFormFlow](/app/models/strata/flows/application_form_flow.rb) | Useful for referencing the current task number within the flow (`#task_counter`) and any defined start/end paths for routing (`#start_path` and `#end_path`) |
| `@flow_page` | [QuestionPage](/app/models/strata/flows/question_page.rb)                | Can be used to reference the page validation context (`#name`) or completion state                                                                           |
| `@flow_task` | [TaskEvaluator](/app/models/strata/flows/task_evaluator.rb)              | Provides routing helpers e.g. `#update_path`, `#prev_path`, and `#next_path`                                                                                 |

Example:

```erb
<%# edit_name.html.erb %>
<%= strata_form_with model: @leave_application_form, url: @flow_task.update_path, method: :patch do |f| %>
  <%= f.name :applicant_name, {
    legend: t(".applicant_name_title"),
    hint: t(".applicant_name_hint"),
    large_legend: true
  } %>

  <%= render partial: "leave_applications/shared/form_buttons", locals: {
    back_path: @flow_task.prev_path || @flow.start_path,
    f: f
  } %>
<% end %>
```

### Defining Model Validations

Multi-page form builder logic is centered around applying updates to a central record based on validation contexts. Each question page sets attributes based on the defined fields and runs validation, e.g. the `name` question page will run with the `:name` validation context.

It's recommended that you include [ApplicationFormValidations](/app/models/strata/flows/application_form_validations.rb) in your record model:

```ruby
class LeaveApplicationForm < ActiveRecord::Base
  include Strata::Flows::ApplicationFormValidations
  validate_flow LeaveApplicationFlow
end
```

This defines a `Flow` constants module for each validation context, which you can reference in validations:

```ruby
validates :applicant_name_first, presence: true, on: Flow::NAME
validates :applicant_name_last, presence: true, on: Flow::NAME
```

By default, `validate_flow` will automatically validate all of the generated contexts upon form submission (i.e. the `:submit` context, which is run in `ApplicationForm#submit_application`).

Use the following option to disable this:

```ruby
validate_flow LeaveApplicationFlow, validate_on_submit: false
```
