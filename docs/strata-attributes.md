# Strata Attributes Documentation

This document provides comprehensive documentation for all Strata Attributes available in the Strata SDK. Strata Attributes are custom data types that extend ActiveRecord with specialized functionality for handling complex data structures commonly used in government and enterprise applications.

## Table of Contents

- [Overview](#overview)
- [Address Attribute](#address-attribute)
- [Array Attribute](#array-attribute)
- [Memorable Date Attribute](#memorable-date-attribute)
- [Money Attribute](#money-attribute)
- [Name Attribute](#name-attribute)
- [Range Attribute](#range-attribute)
- [Tax ID Attribute](#tax-id-attribute)
- [US Date Attribute](#us-date-attribute)
- [Year Month Attribute](#year-month-attribute)
- [Year Quarter Attribute](#year-quarter-attribute)

## Overview

Strata Attributes provide a declarative way to define complex data types in your ActiveRecord models. Each attribute type handles the mapping between a single logical attribute in your model and one or more database columns, along with specialized validation and formatting capabilities.

To use Strata Attributes in your model:

```ruby
class MyModel < ApplicationRecord
  include Strata::Attributes

  strata_attribute :applicant_name, :name
  strata_attribute :home_address, :address
  strata_attribute :salary, :money
end
```

## Address Attribute

The Address Attribute provides structured handling of physical addresses with validation and formatting capabilities.

### Usage in Model

```ruby
class ApplicationForm < Strata::ApplicationForm
  include Strata::Attributes

  strata_attribute :mailing_address, :address
end
```

### Database Mapping

A single `address` attribute creates **5 database columns** using the attribute name as a prefix:

For an attribute named `mailing_address`:

- `mailing_address_street_line_1` (string)
- `mailing_address_street_line_2` (string)
- `mailing_address_city` (string)
- `mailing_address_state` (string)
- `mailing_address_zip_code` (string)

### Available Methods

The `Strata::Address` value object provides:

- `street_line_1`, `street_line_2`, `city`, `state`, `zip_code` - Component accessors
- `to_s` - Returns formatted address string (e.g., "123 Main St, Apt 4B, Anytown, CA 12345")
- `blank?` - Returns true if all components are blank
- `empty?` - Returns true if all components are nil or empty
- `present?` - Returns true if the address has any content

### Usage Examples

```ruby
# Setting an address with a hash
form.mailing_address = {
  street_line_1: "123 Main Street",
  street_line_2: "Apt 4B",
  city: "Anytown",
  state: "CA",
  zip_code: "12345"
}

# Setting an address with a Strata::Address object
form.mailing_address = Strata::Address.new(
  street_line_1: "123 Main Street",
  street_line_2: "Apt 4B",
  city: "Anytown",
  state: "CA",
  zip_code: "12345"
)

# Accessing address components
puts form.mailing_address.city # => "Anytown"
puts form.mailing_address.to_s # => "123 Main Street, Apt 4B, Anytown, CA 12345"
```

### Validation

The Address value object includes built-in validations:

- `street_line_1` - Required
- `city` - Required
- `state` - Required, must be exactly 2 characters
- `zip_code` - Required, must match US zip code format (12345 or 12345-6789)

## Array Attribute

The Array Attribute allows storing arrays of value objects in a single JSONB database column.

### Usage in Model

```ruby
class Company < ApplicationRecord
  include Strata::Attributes

  strata_attribute :office_locations, :address, array: true
  strata_attribute :employee_names, :name, array: true
  strata_attribute :reporting_periods, :year_quarter, array: true
end
```

### Database Mapping

Array attributes create **1 JSONB column**:

- `office_locations` (jsonb)

### Available Methods

Array attributes behave like standard Ruby arrays with automatic serialization/deserialization of the contained value objects.

### Usage Examples

```ruby
# Setting an array of addresses
company.office_locations = [
  Strata::Address.new(street_line_1: "123 Main St", street_line_2: nil, city: "Boston", state: "MA", zip_code: "02108"),
  Strata::Address.new(street_line_1: "456 Oak Ave", street_line_2: "Suite 4", city: "San Francisco", state: "CA", zip_code: "94107")
]

# Array of ranges (complex nested type)
class Enrollment < ApplicationRecord
  include Strata::Attributes

  strata_attribute :leave_periods, [:us_date, range: true], array: true
end

enrollment.leave_periods = [
  Strata::DateRange.new(start: Date.new(2023, 1, 1), end: Date.new(2023, 1, 31)),
  Strata::DateRange.new(start: Date.new(2023, 6, 1), end: Date.new(2023, 6, 30))
]
```

### Validation

Array attributes automatically validate each item in the array using the validation rules of the contained value object type.

## Memorable Date Attribute

The Memorable Date Attribute provides date handling with support for hash input containing separate year, month, and day values.

### Usage in Model

```ruby
class Person < ApplicationRecord
  include Strata::Attributes

  strata_attribute :date_of_birth, :memorable_date
end
```

### Database Mapping

A memorable date attribute creates **1 date column**:

- `date_of_birth` (date)

### Available Methods

Memorable date attributes return standard Ruby `Date` objects with all built-in Date methods available.

### Usage Examples

```ruby
# Setting with a hash (useful for form inputs)
person.date_of_birth = { year: 1990, month: 5, day: 15 }

# Setting with a Date object
person.date_of_birth = Date.new(1990, 5, 15)

# Setting with a string
person.date_of_birth = "1990-05-15"

# Accessing the date
puts person.date_of_birth.year # => 1990
puts person.date_of_birth.strftime("%B %d, %Y") # => "May 15, 1990"
```

### Validation

Memorable date attributes include automatic validation to ensure the date is valid. Invalid dates (like February 30th) will add an `:invalid_date` error to the model.

## Money Attribute

The Money Attribute provides handling of US dollar amounts with automatic conversion between dollars and cents, stored as integers to avoid floating-point precision issues.

### Usage in Model

```ruby
class Employee < ApplicationRecord
  include Strata::Attributes

  strata_attribute :salary, :money
  strata_attribute :bonus, :money
end
```

### Database Mapping

A money attribute creates **1 integer column** that stores the amount in cents:

- `salary` (integer)

### Available Methods

The `Strata::Money` value object provides:

- `cents` - Returns the amount in cents (integer)
- `dollar_amount` - Returns the amount in dollars (BigDecimal)
- `to_s` - Returns formatted currency string (e.g., "$12.50")
- `+`, `-`, `*`, `/` - Arithmetic operations that return new Money objects
- Comparison operators (`<`, `>`, `==`, etc.)

### Usage Examples

```ruby
# Setting with cents
employee.salary = Strata::Money.new(cents: 75000_00) # $75,000.00

# Setting with a hash containing dollar amount
employee.salary = { dollar_amount: 75000.00 }

# Setting with an integer (interpreted as cents)
employee.bonus = 500_00 # $500.00

# Arithmetic operations
total_compensation = employee.salary + employee.bonus
raise_amount = employee.salary * 0.05
monthly_salary = employee.salary / 12

# Formatting
puts employee.salary.to_s # => "$75,000.00"
puts employee.salary.dollar_amount # => 75000.0
puts employee.salary.cents # => 7500000
```

### Validation

Money attributes automatically handle type conversion and validation. Invalid monetary values will be converted to `nil`.

## Name Attribute

The Name Attribute provides structured handling of person names with first, middle, last, and suffix components.

### Usage in Model

```ruby
class Person < ApplicationRecord
  include Strata::Attributes

  strata_attribute :name, :name
  strata_attribute :emergency_contact_name, :name
end
```

### Database Mapping

A single `name` attribute creates **4 database columns** using the attribute name as a prefix:

For an attribute named `name`:
- `name_first` (string)
- `name_middle` (string)
- `name_last` (string)
- `name_suffix` (string)

For an attribute named `owner`:
- `owner_first` (string)
- `owner_middle` (string)
- `owner_last` (string)
- `owner_suffix` (string)

### Available Methods

The `Strata::Name` value object provides:

- `first`, `middle`, `last`, `suffix` - Component accessors
- `full_name` - Returns the complete name with proper spacing
- `to_s` - Alias for `full_name`
- `blank?` - Returns true if all components are blank
- `empty?` - Returns true if all components are nil or empty
- `present?` - Returns true if the name has any content
- Comparison operators for sorting names

### Usage Examples

```ruby
# Setting a name with a hash
person.name = {
  first: "John",
  middle: "A",
  last: "Doe",
  suffix: "Jr."
}

# Setting a name with a Strata::Name object
person.name = Strata::Name.new(first: "John", middle: "A", last: "Doe", suffix: "Jr.")

# Accessing name components
puts person.name.first # => "John"
puts person.name.full_name # => "John A Doe Jr."
puts person.name.to_s # => "John A Doe Jr."

# Names are comparable for sorting
names = [person1.name, person2.name, person3.name]
sorted_names = names.sort # Sorts by last name, then first name, then middle name, then suffix
```

### Validation

Name attributes do not include built-in validation by default, allowing for flexible name formats across different cultures and use cases.

## Range Attribute

The Range Attribute provides handling of value ranges using start and end values, useful for date ranges, number ranges, and other bounded intervals.

### Usage in Model

```ruby
class Enrollment < ApplicationRecord
  include Strata::Attributes

  strata_attribute :coverage_period, :us_date, range: true
  strata_attribute :base_period, :year_quarter, range: true
end
```

### Database Mapping

A range attribute creates **2 columns** for the start and end values:

- `coverage_period_start` (date)
- `coverage_period_end` (date)

### Available Methods

Range attributes return `Strata::ValueRange` objects that provide:

- `start`, `end` - Access to the range boundaries
- `include?` - Check if a value falls within the range
- Standard range operations and comparisons

### Usage Examples

```ruby
# Setting a date range with a hash
enrollment.coverage_period = {
  start: Date.new(2023, 1, 1),
  end: Date.new(2023, 12, 31)
}

# Setting with a ValueRange object
enrollment.coverage_period = Strata::DateRange.new(
  start: Date.new(2023, 1, 1),
  end: Date.new(2023, 12, 31)
)

# Setting with a standard Ruby Range
enrollment.coverage_period = Date.new(2023, 1, 1)..Date.new(2023, 12, 31)

# Accessing range values
puts enrollment.coverage_period.start # => 2023-01-01
puts enrollment.coverage_period.end # => 2023-12-31

# Range operations
if enrollment.coverage_period.include?(Date.today)
  puts "Currently in coverage period"
end
```

### Validation

Range attributes include nested validation of the start and end values using the validation rules of the underlying value type.

## Tax ID Attribute

The Tax ID Attribute provides handling of tax identification numbers (such as Social Security Numbers) with formatting and validation capabilities.

### Usage in Model

```ruby
class Person < ApplicationRecord
  include Strata::Attributes

  strata_attribute :ssn, :tax_id
  strata_attribute :ein, :tax_id
end
```

### Database Mapping

A tax ID attribute creates **1 string column**:

- `ssn` (string)

### Available Methods

The `Strata::TaxId` value object provides:

- `formatted` - Returns the tax ID with dashes in XXX-XX-XXXX format
- `to_s` - Returns the raw digits without formatting
- Comparison operators

### Usage Examples

```ruby
# Setting a tax ID
person.ssn = "123456789"
person.ssn = "123-45-6789" # Dashes are automatically stripped

# Accessing the tax ID
puts person.ssn.to_s # => "123456789" (raw digits)
puts person.ssn.formatted # => "123-45-6789" (formatted with dashes)

# Tax IDs are stored as digits only
person.ssn = "123-45-6789"
puts person.ssn # => "123456789"
```

### Validation

Tax ID attributes include automatic validation to ensure the value contains exactly 9 digits. The validation uses the format `/\A\d{9}\z/` and will add an `:invalid_tax_id` error for invalid formats.

## US Date Attribute

The US Date Attribute provides date handling with US regional format parsing (MM/DD/YYYY) to avoid ambiguity in date interpretation.

### Usage in Model

```ruby
class Application < ApplicationRecord
  include Strata::Attributes

  strata_attribute :submitted_on, :us_date
  strata_attribute :effective_date, :us_date
end
```

### Database Mapping

A US date attribute creates **1 date column**:

- `submitted_on` (date)

### Available Methods

US date attributes return standard Ruby `Date` objects with all built-in Date methods available.

### Usage Examples

```ruby
# Setting with US format string
application.submitted_on = "12/25/2023" # Interpreted as December 25, 2023

# Setting with a Date object
application.submitted_on = Date.new(2023, 12, 25)

# Setting with ISO format string
application.submitted_on = "2023-12-25"

# Accessing the date
puts application.submitted_on.strftime("%m/%d/%Y") # => "12/25/2023"
puts application.submitted_on.year # => 2023
```

### Validation

US date attributes include automatic validation to ensure the date is valid. Invalid dates will add an `:invalid_date` error to the model.

## Year Month Attribute

The Year Month Attribute provides handling of year and month combinations with arithmetic operations and date range conversion capabilities.

### Usage in Model

```ruby
class Report < ApplicationRecord
  include Strata::Attributes

  strata_attribute :activity_reporting_period, :year_month
  strata_attribute :billing_period, :year_month
end
```

### Database Mapping

A year month attribute creates **2 integer columns**:

- `activity_reporting_period_year` (integer)
- `activity_reporting_period_month` (integer)

### Available Methods

The `Strata::YearMonth` value object provides:

- `year`, `month` - Component accessors
- `+`, `-` - Arithmetic operations for month math
- `to_date_range` - Converts to a date range covering the month
- Comparison operators for sorting
- `to_s` - String representation

### Usage Examples

```ruby
# Setting a year month with a hash
report.activity_reporting_period = { year: 2023, month: 6 }

# Setting with a Strata::YearMonth object
report.activity_reporting_period = Strata::YearMonth.new(year: 2023, month: 6)

# Accessing components
puts report.activity_reporting_period.year # => 2023
puts report.activity_reporting_period.month # => 6

# Arithmetic operations
next_month = report.activity_reporting_period + 1 # 2023-07
previous_year_same_month = report.activity_reporting_period - 12 # 2022-06

# Convert to date range
date_range = report.activity_reporting_period.to_date_range
puts date_range.start # => 2023-06-01
puts date_range.end # => 2023-06-30

# Comparison and sorting
months = [june_2023, march_2023, december_2022]
sorted_months = months.sort # Chronological order
```

### Validation

Year Month attributes include validation to ensure the month value is between 1 and 12. Invalid months will add validation errors to the model.

## Year Quarter Attribute

The Year Quarter Attribute provides handling of year and quarter combinations with arithmetic operations and date range conversion capabilities.

### Usage in Model

```ruby
class Report < ApplicationRecord
  include Strata::Attributes

  strata_attribute :reporting_period, :year_quarter
  strata_attribute :comparison_period, :year_quarter
end
```

### Database Mapping

A year quarter attribute creates **2 integer columns**:

- `reporting_period_year` (integer)
- `reporting_period_quarter` (integer)

### Available Methods

The `Strata::YearQuarter` value object provides:

- `year`, `quarter` - Component accessors
- `+`, `-` - Arithmetic operations for quarter math
- `to_date_range` - Converts to a date range covering the quarter
- Comparison operators for sorting
- `to_s` - String representation

### Usage Examples

```ruby
# Setting a year quarter with a hash
report.reporting_period = { year: 2023, quarter: 2 }

# Setting with a Strata::YearQuarter object
report.reporting_period = Strata::YearQuarter.new(year: 2023, quarter: 2)

# Accessing components
puts report.reporting_period.year # => 2023
puts report.reporting_period.quarter # => 2

# Arithmetic operations
next_quarter = report.reporting_period + 1 # 2023 Q3
previous_year_same_quarter = report.reporting_period - 4 # 2022 Q2

# Convert to date range
date_range = report.reporting_period.to_date_range
puts date_range.start # => 2023-04-01 (Q2 starts April 1)
puts date_range.end # => 2023-06-30 (Q2 ends June 30)

# Comparison and sorting
quarters = [q1_2023, q3_2022, q2_2023]
sorted_quarters = quarters.sort # Chronological order
```

### Validation

Year Quarter attributes include validation to ensure the quarter value is between 1 and 4. Invalid quarters will add validation errors to the model.
