# frozen_string_literal: true

module Forge
  module Fixtures
    # Детерминированный пример по IR::Schema, когда в спеке нет examples (docs/OUTPUT_FORMAT.md § 4).
    module Synthesizer
      FORMATS = { 'date-time' => '2026-01-01T00:00:00Z', 'date' => '2026-01-01', 'email' => 'user@example.com',
                  'uri' => 'https://example.com/callback', 'uuid' => '00000000-0000-4000-8000-000000000000' }.freeze
      SCALARS = { 'boolean' => ->(_s) { true }, 'integer' => ->(s) { s.minimum || 1 },
                  'number' => ->(s) { s.minimum || 1.0 } }.freeze

      module_function

      def example(schema, name = 'value')
        return nil if schema.nil?
        return schema.example unless schema.example.nil?
        return schema.enum.first if schema.enum

        by_type(schema, name)
      end

      def by_type(schema, name)
        case schema.type
        when 'object' then (schema.properties || {}).to_h { |key, prop| [key, example(prop, key)] }
        when 'array' then [example(schema.items, name)].compact
        when *SCALARS.keys then SCALARS[schema.type].call(schema)
        else string(schema, name)
        end
      end

      def string(schema, name)
        return FORMATS[schema.format] if FORMATS.key?(schema.format)
        return from_pattern(schema.pattern) if schema.pattern
        return '1.00' if schema.type == 'string' && name.to_s.match?(/amount|sum|total/) # decimal-string суммы

        value = "#{name}_example"
        schema.max_length ? value[0, schema.max_length.clamp(0, 10_000)] : value
      end

      # Простой генератор по регулярке: `^7\d{10}$` → '79000000000', `[A-Z]{2}\d{2}` → 'AA00'.
      def from_pattern(pattern)
        body = pattern.delete_prefix('^').delete_suffix('$').gsub(/\\[Az]/, '')
        body = body.gsub(/\\d\{(\d+)(?:,\d+)?\}/) { '0' * ::Regexp.last_match(1).to_i }
        body = body.gsub(/\[([^\]]+)\]\{(\d+)(?:,\d+)?\}/) do
          first_char(::Regexp.last_match(1)) * ::Regexp.last_match(2).to_i
        end
        body = body.gsub(/\\d[+*]?/, '1').gsub(/\[([^\]]+)\][+*]?/) { first_char(::Regexp.last_match(1)) }
        body = body.gsub(/\((?:\?:)?([^)|]+)(?:\|[^)]*)?\)/, '\1').gsub(/[()?*+]/, '').gsub('\\.', '.')
        return "79#{'0' * 9}" if phone?(pattern, body)

        body.match?(/\A0+\.0+\z/) ? body.sub(/\A0+/, '1') : body
      end

      def phone?(pattern, body) = body.start_with?('7') && pattern.include?('\d{10}')

      def first_char(klass)
        return '0' if klass.start_with?('0-9')
        return 'A' if klass.start_with?('A-Z')
        return 'a' if klass.start_with?('a-z')

        klass[0]
      end
    end
  end
end
