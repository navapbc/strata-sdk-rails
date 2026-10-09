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
- [User Facing ID Attribute](#user-facing-id-attribute)
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

The Name Attribute provides structured handling of person names with first, middle, and last components.

### Usage in Model

```ruby
class Person < ApplicationRecord
  include Strata::Attributes

  strata_attribute :name, :name
  strata_attribute :emergency_contact_name, :name
end
```

### Database Mapping

A single `name` attribute creates **3 database columns** using the attribute name as a prefix:

For an attribute named `name`:
- `name_first` (string)
- `name_middle` (string)
- `name_last` (string)

For an attribute named `owner`:
- `owner_first` (string)
- `owner_middle` (string)
- `owner_last` (string)

### Available Methods

The `Strata::Name` value object provides:

- `first`, `middle`, `last` - Component accessors
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
  last: "Doe"
}

# Setting a name with a Strata::Name object
person.name = Strata::Name.new(first: "John", middle: "A", last: "Doe")

# Accessing name components
puts person.name.first # => "John"
puts person.name.full_name # => "John A Doe"
puts person.name.to_s # => "John A Doe"

# Names are comparable for sorting
names = [person1.name, person2.name, person3.name]
sorted_names = names.sort # Sorts by last name, then first name, then middle name
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

## User Facing ID Attribute

The User Facing ID Attribute provides human-friendly, obfuscated identifiers backed by an integer sequence column. The integer sequence is encoded into a prefixed, segmented string (e.g., `T-Y01-B33-N91`) using a keyed Feistel permutation, so consecutive sequence values produce non-sequential, unpredictable IDs that are safe to expose in URLs and user-facing surfaces.

### Usage in Model

```ruby
class TestRecord < ApplicationRecord
  include Strata::Attributes

  strata_attribute :user_facing_id, :user_facing_id, prefix: "T", key: 0x9b6d_42a7
  strata_attribute :claim_user_facing_id, :user_facing_id, prefix: "CLAIM", key: 0xc7e3_18b5
end
```

### Options

- `prefix` (required) — Uppercase alphanumeric prefix used as the first segment of the formatted ID.
- `key` (required) — Positive integer used to seed the Feistel permutation. There is no default: every attribute must pick a key explicitly. Pass a distinct key per attribute when you want IDs from different attributes to occupy independent encoding spaces. Once an ID has been issued for a given attribute, the key must not be changed — previously issued IDs are bound to the key they were encoded with.
- `sequence_column` (optional) — Name of the backing integer column. Defaults to `"#{name}_sequence"`.
- `alphabet` (optional) — Array of uppercase A-Z letters that may appear in the encoded ID. Defaults to `Strata::UserFacingId::Alphabet::DEFAULT` (A-Z minus "I"). Pass a custom alphabet when you want to drop additional confusable letters (for example, "O" vs. "0"). Must be unique single-character uppercase strings, between 1 and 26 letters long. Like `key`, once IDs have been issued for an attribute the alphabet must not be changed — previously issued IDs are bound to the alphabet they were encoded with. See [Alphabet and Capacity](#alphabet-and-capacity) below for the trade-offs of smaller alphabets.

### Database Mapping

A user facing ID attribute is backed by **1 integer column** (typically a `bigserial` so Postgres assigns sequence values automatically):

For an attribute named `user_facing_id`:

- `user_facing_id_sequence` (bigserial / integer)

The encoded string is computed on read; it is not stored in the database.

Example migration:

```ruby
class AddUserFacingIdSequenceToTestRecords < ActiveRecord::Migration[8.0]
  def up
    add_column :test_records, :user_facing_id_sequence, :bigserial, null: false
    add_index :test_records, :user_facing_id_sequence, unique: true
  end

  def down
    remove_index :test_records, :user_facing_id_sequence
    remove_column :test_records, :user_facing_id_sequence
  end
end
```

### Available Methods

- The attribute reader (e.g., `record.user_facing_id`) returns the formatted, prefixed string.
- The sequence reader (e.g., `record.user_facing_id_sequence`) returns the underlying integer.
- The attribute writer accepts either the formatted string or an integer sequence value and stores the integer.
- Querying through the attribute (e.g., `Model.where(user_facing_id: "T-Y01-B33-N91")`) decodes the formatted ID to its sequence integer before comparing against the column.

### Usage Examples

```ruby
# Reading
record.user_facing_id          # => "T-Y01-B33-N91"
record.user_facing_id_sequence # => 1

# Assigning a formatted string (decodes to the underlying sequence integer)
record.user_facing_id = "T-Y01-B33-N91"
record.user_facing_id_sequence # => 1

# Assigning an integer sequence directly
record.user_facing_id = 42
record.user_facing_id_sequence # => 42

# Querying by formatted ID
TestRecord.find_by(user_facing_id: "T-Y01-B33-N91")
```

### Validation

The prefix is validated at model load time and must contain only letters and digits (`/\A[A-Z0-9]+\z/`); invalid prefixes raise `Strata::UserFacingId::FormatError`.

The alphabet is also validated at model load time. It must be an Array of unique single-character uppercase A-Z strings, between 1 and 26 entries long; anything else raises `Strata::UserFacingId::FormatError`.

At runtime:

- Assigning a malformed formatted string raises `Strata::UserFacingId::Error` (loud failure for debuggability).
- Querying with a malformed formatted string casts to `nil` so the query simply returns no results rather than raising.
- Sequence values must fall within the attribute's capacity range; out-of-range values raise `RangeError` during encoding. The capacity is per-attribute and depends on the configured alphabet — see [Alphabet and Capacity](#alphabet-and-capacity).

### Alphabet and Capacity

The alphabet controls which letters may appear in encoded IDs. The default (`Strata::UserFacingId::Alphabet::DEFAULT`) is the 25-letter set `A-Z` minus `"I"`, dropping `"I"` because it is easy to confuse with the digit `1` when an ID is read aloud, written by hand, or printed in a narrow font. Many teams want the same treatment for other confusable letters:

- `"O"` vs. the digit `0`
- `"S"` vs. the digit `5`
- `"Z"` vs. the digit `2`
- `"B"` vs. the digit `8`

You can drop any letters you like by passing your own alphabet:

```ruby
class TestRecord < ApplicationRecord
  include Strata::Attributes

  # Default alphabet minus "O" — 24 letters, ~864 million IDs available.
  strata_attribute :user_facing_id, :user_facing_id,
    prefix: "T",
    key: 0x9b6d_42a7,
    alphabet: %w[A B C D E F G H J K L M N P Q R S T U V W X Y Z]
end
```

#### How the alphabet affects capacity

Every ID is a prefix plus three segments of one letter and two digits (e.g., `T-Y01-B33-N91`). So the total number of *distinct* IDs an attribute can produce is roughly `(letters_in_alphabet * 100) ^ 3 / 16` — three independent segments, each with `letters * 100` possible values, divided by 16 because the codec reserves four bits for an error-detection checksum.

Removing a letter shrinks each segment's possibilities, and because there are three segments, the total capacity shrinks by *roughly* the cube of that ratio:

- Dropping one letter (25 → 24) costs about **12%** of capacity
- Dropping two letters (25 → 23) costs about **22%** of capacity
- Dropping five letters (25 → 20) costs about **49%** of capacity

In practice, every supported alphabet still leaves room for hundreds of millions of IDs per attribute — more than enough for almost any application — but it is worth knowing the trade-off when picking how aggressive to be about excluding confusable letters.

#### Capacity table

| Alphabet length | Example exclusions | Max sequence value (per attribute) | Approximate IDs available |
|---|---|---|---|
| 26 (full A-Z) | none (includes "I") | 1,073,741,823 | ~1.07 billion (Feistel ceiling) |
| 25 (default) | "I" | 976,562,499 | ~976 million |
| 24 | "I", "O" | 863,999,999 | ~864 million |
| 23 | "I", "O", "S" | 760,437,499 | ~760 million |
| 22 | "I", "O", "S", "Z" | 665,499,999 | ~665 million |
| 20 | "I", "O", "S", "Z" + 2 more | 499,999,999 | ~500 million |

#### Upper limit: 26 letters

The encoder uses a 30-bit Feistel permutation under the hood, which caps the encodable space at `2^30 = 1,073,741,824` values. A full 26-letter alphabet would technically allow `(26 * 100)^3 / 16 ≈ 1.10 billion` IDs by the segment math, but the Feistel ceiling binds first, so the effective limit for a 26-letter alphabet is the Feistel ceiling (`Strata::UserFacingId::Feistel::DOMAIN_SIZE - 1`). Going from 25 to 26 letters therefore only buys you about 10% more capacity, not the 12% the cube would suggest. Alphabets longer than 26 letters are rejected at model load time.

#### Picking an alphabet — guidance

- The default (`A-Z` minus `"I"`) is a reasonable starting point for most applications.
- If your IDs will be read aloud, dictated over the phone, or copied by hand, dropping `"O"` and `"S"` is usually worth the ~22% capacity hit. The result is still ~760 million IDs.
- If your IDs only ever appear in URLs or copy/pasted from a UI, the default is fine — confusable letters are less of a problem when humans never re-type the ID.
- Avoid going below 20 letters unless you have a very small expected ID volume. The 30-bit permutation domain stays the same regardless of alphabet, so cycle-walk rejection rates climb steeply at small alphabet sizes, slowing encoding (though never enough to be noticeable in normal application use).

#### Don't change the alphabet after issuance

Just like `key`, the alphabet is part of the encoding contract. Once an attribute has issued IDs to users, changing the alphabet will make every previously issued ID undecodable — the backing sequence column is unaffected, but `find_by(user_facing_id: "...")` queries from emails, bookmarks, or older URLs will silently return no results. Pick the alphabet you want before going to production and treat it as immutable from that point on.

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
