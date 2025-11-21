# Strata Generators Guide

This document provides an overview of all available generators in the Strata SDK and guidance on which ones to use when starting a new project. For each generator, you can click through to see detailed usage instructions and examples.

## Quick Start Guide

When starting a new project with Strata, you'll typically want to follow this order:

1. Generate your application form using [`strata:application_form`](../lib/generators/strata/application_form/USAGE)
2. Generate your case model using [`strata:case`](../lib/generators/strata/case/USAGE)
3. Generate your business process using [`strata:business_process`](../lib/generators/strata/business_process/USAGE)
4. Add any additional tasks using [`strata:task`](../lib/generators/strata/task/USAGE)

## Available Generators

### strata:application_form

Creates a new application form model that extends `Strata::ApplicationForm`. This is typically your starting point for collecting user input data. [See full usage guide](../lib/generators/strata/application_form/USAGE)

```bash
bin/rails generate strata:application_form NAME [attribute:type attribute:type] [options]
```

### strata:case

Generates a Strata::Case model with optional business process and application form integration. Cases are the core models that represent your business entities. [See full usage guide](../lib/generators/strata/case/USAGE)

```bash
bin/rails generate strata:case NAME [attributes] [options]
```

### strata:business_process

Creates a business process file that defines the workflow and event handling for your cases. This generator automatically configures your Rails application to listen for events. [See full usage guide](../lib/generators/strata/business_process/USAGE)

```bash
bin/rails generate strata:business_process NAME [options]
```

### strata:task

Generates a Strata::Task subclass for implementing specific workflow tasks. Tasks are individual units of work within your business process. [See full usage guide](../lib/generators/strata/task/USAGE)

```bash
bin/rails generate strata:task NAME [options]
```

### strata:model

Creates a Rails model with support for Strata attributes like `:name`, `:address`, `:money`, etc. This is useful for creating supporting models that need Strata's specialized attribute types. [See full usage guide](../lib/generators/strata/model/USAGE)

```bash
bin/rails generate strata:model NAME [attribute:type attribute:type] [options]
```

### strata:migration

Creates Rails migrations with appropriate database columns for Strata attributes. This generator automatically maps Strata attribute types to their required database columns. [See full usage guide](../lib/generators/strata/migration/USAGE)

```bash
bin/rails generate strata:migration NAME [attribute:type attribute:type] [options]
```

### strata:income_records_migration

Specialized migration generator for creating income record tables with support for different period types (year_quarter or date_range). [See full usage guide](../lib/generators/strata/income_records_migration/USAGE)

```bash
bin/rails generate strata:income_records_migration NAME period_type
```

### strata:staff

Creates a standard set of files required for implementing a staff dashboard in applications using the `strata` gem. This generator scaffolds controllers, views, and tests for staff task management. [See full usage guide](../lib/generators/strata/staff/USAGE)

```bash
bin/rails generate strata:staff
```

## Generator Dependencies

- When generating a case, the generator will check for the existence of associated business process and application form classes
- The task generator will verify the existence of the strata_tasks table
- All generators that create models will automatically create the necessary database migrations

## Commonly Used Strata Attribute Types

The following attribute types are supported across various generators:

- `name` - Creates columns for first, middle, and last name
- `address` - Creates columns for street lines, city, state, and zip code
- `money` - Creates an integer column (stores cents)
- `memorable_date` - Creates a date column
- `tax_id` - Creates a string column
- `year_quarter` - Creates year and quarter integer columns
- `date_range` - Creates start and end date columns
- `array` - Creates a jsonb column for storing arrays of objects

For more details on each generator, you can run:

```bash
bin/rails generate strata:[generator_name] --help
```
