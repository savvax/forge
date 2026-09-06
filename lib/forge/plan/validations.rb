# frozen_string_literal: true

module Forge
  module Plan
    # Предпроверки check_conditions из схемы запроса: min/max суммы, maxLength, pattern, enum валюты.
    module Validations
      module_function

      def build(fields, amount)
        skip = /\Acredentials\.|\Acallback_url\z/
        mappings = fields[:request].reject { |m| m.source_expr.nil? || m.source_expr.match?(skip) }
        amount_rules(mappings, amount) + mappings.reject { |m| m.transform == 'amount' }.flat_map { |m| field_rules(m) }
      end

      def amount_rules(mappings, amount)
        mapping = mappings.find { |m| m.transform == 'amount' }
        return [] unless mapping

        rules = []
        rules << rule(mapping, :min, amount[:minimum_major], 'amount_too_low') if meaningful_min?(amount)
        rules << rule(mapping, :max, amount[:maximum_major], 'amount_too_high') if amount[:maximum_major]
        rules
      end

      # Минимум в одну минорную единицу (0.01) уже покрыт проверкой amount.positive? в BaseService.
      def meaningful_min?(amount)
        amount[:minimum_major] && (amount[:minimum_major].to_r * (amount[:multiplier] || 100)).round > 1
      end

      def field_rules(mapping)
        schema = mapping.schema
        rules = []
        if schema.max_length
          rules << rule(mapping, :max_length, schema.max_length,
                        "#{Rules.normalize(mapping.provider_field)}_too_long")
        end
        if schema.pattern
          rules << rule(mapping, :pattern, schema.pattern, "#{Rules.normalize(mapping.provider_field)}_invalid")
        end
        if currency?(mapping) && schema.enum
          rules << rule(mapping, :enum, schema.enum.map(&:to_s),
                        'currency_not_supported')
        end
        rules
      end

      def currency?(mapping) = mapping.source_expr == 'operation.currency'

      def rule(mapping, kind, value, code)
        { field: mapping.path.join('.'), rule: kind, value: value, error_code: code, expr: mapping.source_expr,
          requisite_type: mapping.requisite_type, required_if: mapping.required_if }
      end
    end
  end
end
