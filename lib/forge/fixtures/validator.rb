# frozen_string_literal: true

module Forge
  module Fixtures
    # Проверка примеров fixtures.json по IR::Schema: типы, required, enum. Без внешних гемов (json_schemer не нужен).
    # → массив строк-несоответствий ("create_request.request.amount: expected integer, got String").
    module Validator
      module_function

      def check(value, schema, path = 'value')
        return [] if schema.nil? || value.nil?
        return check_object(value, schema, path) if schema.type == 'object' || schema.properties
        return check_array(value, schema, path) if schema.type == 'array'

        [*type_error(value, schema, path), *enum_error(value, schema, path)]
      end

      def check_object(value, schema, path)
        return ["#{path}: expected object, got #{value.class}"] unless value.is_a?(Hash)

        missing = schema.required.to_a.reject { |k| value.key?(k) }.map { |k| "#{path}.#{k}: required field missing" }
        nested = value.flat_map do |k, v|
          schema.properties.to_h[k] ? check(v, schema.properties[k], "#{path}.#{k}") : []
        end
        missing + nested
      end

      def check_array(value, schema, path)
        return ["#{path}: expected array, got #{value.class}"] unless value.is_a?(Array)

        value.each_with_index.flat_map { |v, i| check(v, schema.items, "#{path}[#{i}]") }
      end

      TYPES = { 'string' => [String], 'integer' => [Integer], 'number' => [Integer, Float, Rational],
                'boolean' => [TrueClass, FalseClass] }.freeze

      def type_error(value, schema, path)
        expected = TYPES[schema.type]
        return [] if expected.nil? || expected.any? { |klass| value.is_a?(klass) }

        ["#{path}: expected #{schema.type}, got #{value.class}"]
      end

      def enum_error(value, schema, path)
        return [] if schema.enum.nil? || schema.enum.map(&:to_s).include?(value.to_s)

        ["#{path}: '#{value}' is not in enum #{schema.enum.join('|')}"]
      end
    end
  end
end
