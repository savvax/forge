# frozen_string_literal: true

module Forge
  module IR
    Schema = Data.define(:ref_name, :type, :format, :description, :properties, :required, :items, :enum,
                         :minimum, :maximum, :min_length, :max_length, :pattern, :multiple_of, :example,
                         :nullable, :one_of, :any_of, :all_of, :additional, :unresolved_ref, :circular_ref) do
      # Hash из спеки (после RefResolver) → Schema. allOf сливается, oneOf/anyOf остаются списками.
      # Мемоизация по identity: RefResolver разделяет цели ссылок, без кэша большие спеки строятся экспоненциально.
      def self.from(hash)
        hash = {} if hash == true # JSON Schema: `true` = любое значение
        return nil unless hash.is_a?(Hash)

        memo = (Thread.current[:forge_schema_memo] ||= {}.compare_by_identity)
        memo[hash] ||= build(hash)
      end

      def self.build(hash)
        hash = merge_all_of(hash) if hash['allOf']
        type, nullable = split_type(hash['type'], hash['nullable'])
        new(**scalars(hash), type: type, nullable: nullable, ref_name: hash['x-forge-ref-name'],
                             properties: hash['properties']&.transform_values do |v|
                               from(v.nil? ? {} : v) # `name:` без схемы = любое значение
                             end, items: from(hash['items']),
                             one_of: list(hash['oneOf']), any_of: list(hash['anyOf']), all_of: nil,
                             additional: hash['additionalProperties'], unresolved_ref: hash['x-forge-unresolved'],
                             circular_ref: hash['x-forge-circular'])
      end

      def self.scalars(hash)
        { format: hash['format'], description: hash['description'], required: hash['required'], enum: hash['enum'],
          minimum: hash['minimum'], maximum: hash['maximum'], min_length: hash['minLength'],
          max_length: hash['maxLength'], pattern: hash['pattern'], multiple_of: hash['multipleOf'],
          example: hash['example'] }
      end

      def self.list(items) = items&.map { |i| from(i) }

      # OpenAPI 3.1: type: ['string', 'null'] → 'string' + nullable.
      def self.split_type(type, nullable)
        return [type, nullable == true] unless type.is_a?(Array)

        [(type - ['null']).first, type.include?('null') || nullable == true]
      end

      # allOf: части сливаются слева направо (properties/required объединяются), затем собственные ключи.
      def self.merge_all_of(hash)
        parts = hash['allOf'].map { |p| p == true ? {} : p }.map { |p| p['allOf'] ? merge_all_of(p) : p }
        merged = [*parts, hash.except('allOf')].reduce({}) { |acc, part| merge_part(acc, part) }
        merged['type'] ||= 'object'
        merged
      end

      def self.merge_part(acc, part)
        acc.merge(part) do |key, old, new|
          case key
          when 'properties' then old.merge(new)
          when 'required' then (old + new).uniq
          else new
          end
        end
      end
    end
  end
end
