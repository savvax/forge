# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Поле суммы запроса create: minor/major единицы, множитель валюты, минимум (rules/amount_units.yml).
    class Amount < Base
      def call
        path, field = locate(role(:create)&.request_body&.schema)
        return not_found unless field

        unit, confidence = decide(field)
        currency_path, currencies = currency(path)
        multiplier = 10**exponent(currencies.first)
        value = { field: path.last, path: path, unit: unit, multiplier: multiplier, currencies: currencies,
                  currency_field: currency_path&.join('.'), type: field.type, expr: expression(unit, field),
                  minimum_major: major(field.minimum, unit, multiplier),
                  maximum_major: major(field.maximum, unit, multiplier) }
        finding(:amount, value, confidence: confidence, source: source_text(path, field, unit))
      end

      private

      def dict = rules.fetch(:amount_units)
      def alias_names(name) = rules.fetch(:field_aliases).dig('aliases', name, 'names')

      # → [path, Schema] первого свойства с именем-алиасом суммы (в т. ч. amount.value).
      def locate(schema)
        @properties = walk(schema)
        @properties.find { |path, prop| alias_names('amount').include?(path.join('.')) && prop.type != 'object' } ||
          [nil, nil]
      end

      def walk(schema, prefix = [])
        return [] unless schema&.properties

        schema.properties.flat_map do |name, prop|
          path = prefix + [name]
          [[path, prop]] + (prop.type == 'object' && prefix.empty? ? walk(prop, path) : [])
        end
      end

      def decide(field)
        minor = Scorer.minor(field, dict)
        major = Scorer.major(field, dict)
        best = [minor, major].max
        return [minor >= major ? :minor : :major, best.clamp(0.0, 1.0).round(2)] if best >= threshold(:warn)

        default = dict['default']
        warn(default['warning'].to_sym, "amount unit not stated (#{field.description || field.type}); major assumed",
             hint: 'amount.unit: minor|major  (overrides.yml)')
        [default['unit'].to_sym, default['confidence']]
      end

      def currency(amount_path)
        candidates = @properties.select { |path, _| alias_names('currency').include?(path.join('.')) }
        sibling = candidates.find { |path, _| path[0..-2] == amount_path[0..-2] } || candidates.first
        return [nil, []] unless sibling

        [sibling[0], Array(sibling[1].enum).map(&:to_s)]
      end

      def exponent(code) = rules.fetch(:currency_exponents).fetch(code) { rules.fetch(:currency_exponents)['default'] }

      def major(limit, unit, multiplier)
        return nil unless limit

        unit == :minor ? limit / multiplier : limit
      end

      def expression(unit, field)
        return 'to_minor_units(operation.amount)' if unit == :minor
        return "format('%.2f', operation.amount)" if field.type == 'string'

        'operation.amount'
      end

      def not_found
        warn(:amount_field_not_found, 'no amount field in the create request schema', hint: 'fields.<path>.source: "…"')
        value = { field: nil, path: nil, unit: :major, multiplier: 100, currencies: [], expr: 'operation.amount' }
        finding(:amount, value, confidence: 0.0, source: 'amount field not found')
      end

      def source_text(path, field, unit)
        "#{path.join('.')} (#{field.type}#{", min #{field.minimum}" if field.minimum}) → #{unit} units" \
          "#{": '#{field.description}'" if field.description}"
      end

      # Очки minor/major по сигналам словаря.
      module Scorer
        module_function

        def minor(field, dict)
          w = dict['signals']
          (marker(field, dict['minor_markers']) * w['minor_marker_in_description']) +
            (field.type == 'integer' ? w['integer_type'] : 0) +
            (field.type == 'integer' && field.minimum.to_i >= 1000 ? w['integer_with_minimum_ge_1000'] : 0)
        end

        def major(field, dict)
          w = dict['signals']
          (marker(field, dict['major_markers']) * w['major_marker_in_description']) +
            (decimal?(field) ? w['decimal_pattern'] : 0) +
            (field.multiple_of.to_f.between?(0.009, 0.011) ? w['multiple_of_cent'] : 0) +
            (field.type == 'number' ? w['number_type'] : 0)
        end

        def marker(field, markers)
          text = field.description.to_s.downcase
          markers.any? { |m| text.include?(m.downcase) } ? 1 : 0
        end

        def decimal?(field) = field.type == 'string' && field.pattern.to_s.include?('\d{2}')
      end
    end
  end
end
