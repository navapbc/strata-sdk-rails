# Strata Data Modeler

The Strata Data Modeler simplifies the process of defining data models for your application. It provides built-in support for common attribute types and ensures data interoperability by leveraging Strata data standards.

## Strata Attributes

Strata Attributes extend ActiveRecord with custom attribute types, providing a consistent interface for defining specialized attributes like memorable dates, names, addresses, tax IDs, and money amounts.

### Example Usage

To use Strata Attributes in a model:

```ruby
class MyModel < ApplicationRecord
  include Strata::Attributes

  strata_attribute :birth_date, :memorable_date
  strata_attribute :applicant_name, :name
  strata_attribute :salary, :money
end
```

This allows you to define attributes with specialized behavior and column mappings, simplifying the process of working with complex data types.

## Supported Attribute Types

See the [Strata Attributes](./strata-attributes.md) documentation for a complete list of supported attribute types and their column mappings.

## Strata Migration Generator

The Strata SDK provides a Rails generator to automatically create database migrations with the correct column definitions for Strata attributes. It also works with regular Rails attribute types.

### Usage

```shell
bin/rails generate strata:migration AddAttributesToTableName attribute_name:attribute_type
```

### Example

```shell
bin/rails generate strata:migration AddPersonalInfoToUsers name:name date_of_birth:memorable_date address:address email:string
```

This generates a migration with the appropriate columns:

- `name_first`, `name_middle`, `name_last`, `name_suffix` (string columns for the name attribute)

- `date_of_birth` (date column for the memorable_date attribute)  

- `address_street_line_1`, `address_street_line_2`, `address_city`, `address_state`, `address_zip_code` (string columns for the address attribute)

- `email` (string column for the email attribute)

For a complete list of supported attribute types and their column mappings, run:

```shell
bin/rails generate strata:migration --help
```
