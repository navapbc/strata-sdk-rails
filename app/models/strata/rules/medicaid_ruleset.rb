# frozen_string_literal: true

module Strata
  module Rules
    # Implements eligibility rules for Medicaid benefits.
    # Handles age calculations, residency verification, and income-based qualification.
    class MedicaidRuleset
      def medicaid_eligibility(state_of_residence, age_over_65, modified_adjusted_gross_income)
        age_over_65 && modified_adjusted_gross_income < 50000
      end

      def age(date_of_birth, evaluated_on)
        return nil if date_of_birth.nil? || evaluated_on.nil?
        return nil if date_of_birth > evaluated_on

        value = evaluated_on.year - date_of_birth.year
        value -= 1 if evaluated_on < date_of_birth + value.years
        value
      end

      def age_over_65(age)
        return nil if age.nil?
        age >= 65
      end

      def state_of_residence(residential_address)
        residential_address&.state
      end

      def modified_adjusted_gross_income(annual_income, deductions)
        return nil if annual_income.nil? || deductions.nil?
        return 0 if annual_income < deductions
        annual_income - deductions
      end
    end
  end
end
