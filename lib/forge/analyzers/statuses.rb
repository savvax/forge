# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Поле статуса в ответе (enum или description) → словарь rules/status_map.yml; путь к id ответа.
    class Statuses < Base
      QUOTED = /[`'"]([A-Za-z_][\w.-]*)[`'"]/
      ID_TESTS = [[->(p, _d) { p == ['id'] }, 0.95],
                  [->(p, d) { p.size == 1 && d.include?(p.first) }, 0.85],
                  [->(p, d) { p.size > 1 && d.include?(p.last) }, 0.8]].freeze

      def call
        schema = success_response(role(:status) || role(:create))&.schema
        path, field, confidence = locate(schema)
        values = field ? enum_or_description(field, path) : []
        map, unmapped = classify(values, path)
        id_path, id_confidence = response_id(schema)
        value = { field_path: path, map: map, unmapped: unmapped, response_id_path: id_path,
                  response_status_path: path, response_id_confidence: id_confidence }
        finding(:statuses, value, confidence: confidence, source: source_text(path, field, values))
      end

      private

      def dict = rules.fetch(:status_map)

      # → [path, schema, confidence]; без поля — ['status'], nil, 0.0 + WARN.
      def locate(schema)
        found = find_property(schema, dict['status_fields'], require: :enum) ||
                find_property(schema, dict['status_fields'], require: :description)
        return found if found

        warn(:status_field_not_found, 'no status field (enum or described) found in the response schema',
             hint: 'statuses.field: <path>  (overrides.yml)')
        [['status'], nil, 0.0]
      end

      def find_property(schema, names, require:)
        candidates(schema).each do |path, prop|
          next unless status_path?(path, names) && string_like?(prop)

          confidence = property_confidence(prop, require)
          return [path, prop, confidence] if confidence
        end
        nil
      end

      # `status` / `data.state` / `status.value` (объект статуса с полем value).
      def status_path?(path, names)
        names.include?(path.last) || (path.last == 'value' && path.size > 1 && names.include?(path[-2]))
      end

      # Корневой `status: true` (обёртка status: true в ответе) — не статус выплаты.
      def string_like?(prop) = !%w[boolean integer number object array].include?(prop.type)

      def property_confidence(prop, require)
        return 0.95 if require == :enum && prop.enum
        return 0.6 if require == :description && prop.description.to_s.match?(QUOTED)

        nil
      end

      # Свойства корня и внутри wrappers (глубина ≤ 2): [[path, schema], ...]
      # Обходим wrappers (data, result…) и объект статуса вида `status: {value: enum}` (объект статуса с полем value).
      def candidates(schema, prefix = [], depth = 0)
        return [] unless schema&.properties

        schema.properties.flat_map do |name, prop|
          nested = depth < 2 && descend?(name, prop) ? candidates(prop, prefix + [name], depth + 1) : []
          [[prefix + [name], prop]] + nested
        end
      end

      def descend?(name, prop)
        dict['wrappers'].include?(name) || (dict['status_fields'].include?(name) && prop.properties&.key?('value'))
      end

      def enum_or_description(field, path)
        return field.enum.map(&:to_s) if field.enum

        values = field.description.scan(QUOTED).flatten.uniq
        warn(:status_from_description, "statuses of #{path.join('.')} taken from description: #{values.join(', ')}",
             hint: 'verify the list; statuses.<VALUE>: in_progress|approved|rejected (overrides.yml)')
        values
      end

      def classify(values, path)
        map = {}
        unmapped = []
        values.each do |value|
          internal = %w[in_progress approved rejected].find { |k| dict[k].include?(Rules.normalize(value)) }
          internal ? map[value] = internal : unmapped << value
        end
        unmapped.each { |v| unmapped_warning(v, path) }
        [map, unmapped]
      end

      def unmapped_warning(value, path)
        warn(:unmapped_status, "status '#{value}' (#{Rules.normalize(value)}) of #{path.join('.')} is unknown",
             hint: "statuses.#{value}: in_progress|approved|rejected  (overrides.yml)")
      end

      def response_id(schema)
        paths = candidates(schema).map(&:first)
        found = ID_TESTS.lazy.filter_map do |test, conf|
          (path = paths.find do |p|
            test.call(p, dict['id_fields'])
          end) && [path, conf]
        end
                        .first
        return found if found

        warn(:response_id_not_found, 'no id field found in the response schema; `id` assumed',
             hint: 'statuses.response_id: <path>  (overrides.yml)')
        [['id'], 0.0]
      end

      def source_text(path, field, values)
        return 'status field not found' unless field

        "#{path.join('.')} #{field.enum ? 'enum' : 'description'}: #{values.join(', ')}"
      end
    end
  end
end
