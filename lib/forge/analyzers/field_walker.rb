# frozen_string_literal: true

module Forge
  module Analyzers
    # Обход схемы запроса create: свойство → FieldMapping. Реквизиты — внутри контейнеров (recipient, destination…).
    class FieldWalker
      attr_reader :container

      def self.match?(names, path)
        normalized = path.map { |p| Rules.normalize(p) }
        names.any? { |n| n == normalized.last || n == normalized.last(2).join('.') }
      end

      def initialize(analyzer, dict, amount_expr)
        @analyzer = analyzer
        @dict = dict
        @amount_expr = amount_expr
      end

      # requisite: nil (вне контейнера) | :any (тип неизвестен) | 'sbp' | 'card' | ...
      def walk(schema, prefix, required, requisite)
        schema.properties.to_h.flat_map do |name, prop|
          path = prefix + [name]
          req = required.include?(name)
          node(path, prop, req, requisite)
        end
      end

      private

      def node(path, prop, req, requisite)
        return [array(path, prop, req)] if prop.type == 'array'
        return walk_container(path, prop, requisite) if container?(path.last, prop, requisite)
        return variant(path, prop, requisite) if prop.one_of || prop.any_of
        return walk(prop, path, prop.required.to_a, nil) if prop.type == 'object' && !requisite

        [leaf(path, prop, req, requisite)]
      end

      def container?(name, prop, requisite)
        return false unless prop.type == 'object'

        @dict['requisite_container'].include?(name) || (requisite && @dict['requisite_types'].include?(name))
      end

      def walk_container(path, prop, requisite)
        @container ||= path.join('.')
        type = @dict['requisite_types'].include?(path.last) ? path.last : requisite
        backfill(walk(prop, path, prop.required.to_a, type || :any))
      end

      def variant(path, prop, requisite)
        options = prop.one_of || prop.any_of
        first = options.first
        @analyzer.warn_variant(path, options, first)
        @container ||= path.join('.')
        backfill(walk(first, path, first.required.to_a, requisite || :any))
      end

      # Контейнер без поля типа и с единственным выведенным типом: нетипизированные поля получают его же.
      def backfill(mappings)
        types = mappings.filter_map(&:requisite_type).uniq
        return mappings if types.size != 1 || mappings.any? { |m| m.source_expr == 'requisite_type' }

        mappings.map { |m| retype(m, types.first) }
      end

      def retype(mapping, type)
        return mapping unless mapping.source_expr&.include?('dig(requisite_type,')

        mapping.with(requisite_type: type, source_expr: mapping.source_expr.sub('requisite_type', "'#{type}'"))
      end

      def array(path, prop, req)
        @analyzer.warn_array(path)
        mapping(path, '[]', req, prop, 0.3)
      end

      def leaf(path, prop, req, requisite)
        return requisite_leaf(path, prop, req, requisite) if requisite

        _name, rule = @dict['aliases'].find { |_n, r| self.class.match?(r['names'], path) }
        return unmapped(path, prop, req) unless rule

        @analyzer.info_credential(path) if rule['info']
        expr = format(rule['expr'], amount_expr: @amount_expr, name: path.last)
        mapping(path, expr, req, prop, 0.95, transform: rule['transform'])
      end

      def requisite_leaf(path, prop, req, requisite)
        return mapping(path, 'requisite_type', req, prop, 0.95) if type_field?(path)

        _key, rule = @dict['requisite_fields'].find { |_n, r| self.class.match?(r['names'], path) }
        return unmapped(path, prop, req) unless rule

        condition = required_if(path, prop)
        type = condition ? condition[:equals] : resolve_type(requisite, rule)
        mapping(path, dig_expr(type, rule['field']), req && !condition, prop, condition ? 0.6 : 0.9,
                required_if: condition, requisite_type: type)
      end

      def dig_expr(type, field) = "operation.payout_requisite.dig(#{type ? "'#{type}'" : 'requisite_type'}, '#{field}')"

      def type_field?(path) = self.class.match?(@dict.dig('requisite_type', 'names'), path)
      def resolve_type(requisite, rule) = requisite == :any ? Array(rule['types']).first : requisite

      def required_if(path, prop)
        text = prop.description.to_s
        patterns = @dict['conditional_required_patterns']
        match = patterns.lazy.filter_map { |re| text.match(Regexp.new(re, Regexp::IGNORECASE)) }.first
        return nil unless match

        @analyzer.warn_conditional(path, match)
        { field: match[:field], equals: match[:value] }
      end

      def unmapped(path, prop, req)
        @analyzer.warn_unmapped(path, prop)
        mapping(path, nil, req, prop, 0.0)
      end

      def mapping(path, expr, req, prop, confidence, transform: nil, required_if: nil, requisite_type: nil)
        FieldMapping.new(provider_field: path.last, path: path, source_expr: expr, required: req,
                         required_if: required_if, transform: transform, schema: prop, confidence: confidence,
                         requisite_type: requisite_type)
      end
    end
  end
end
