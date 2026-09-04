# frozen_string_literal: true

require_relative 'base'
require_relative 'field_walker'

module Forge
  FieldMapping = Data.define(:provider_field, :path, :source_expr, :required, :required_if, :transform, :schema,
                             :confidence, :requisite_type)

  module Analyzers
    # Поля запроса create → выражения operation.* (rules/field_aliases.yml); реквизиты по типам; заголовки.
    class Fields < Base
      HINT_MISSING = 'check the pointer: the target must exist in this document'
      HINT_EXTERNAL = 'inline the referenced schema into the spec or bundle it with a resolver'
      HINT_CYCLE = 'break the cycle in the request schema: inline one side or drop the back-reference'

      def call
        endpoint = role(:create)
        schema = endpoint&.request_body&.schema
        check_external_refs(endpoint, schema)
        walker = FieldWalker.new(self, dict, amount_expr)
        request = schema ? walker.walk(schema, [], schema.required.to_a, nil) : []
        value = { request: request, requisite_types: requisite_types(request), requisite_container: walker.container,
                  headers: headers(endpoint) }
        finding(:fields, value, confidence: request.empty? ? 0.0 : mean(request),
                                source: "#{request.size} request fields mapped")
      end

      # Публичные для FieldWalker: предупреждения с накоплением в этом анализаторе.
      def warn_unmapped(path, prop)
        detail = [prop.type, prop.description].compact.join(', ')
        warn(:unmapped_field, "#{path.join('.')} (#{detail}) has no source",
             hint: "fields.#{path.join('.')}.source: \"…\"  (overrides.yml)")
      end

      def warn_array(path)
        warn(:array_field_unsupported, "#{path.join('.')} is an array; [] is generated",
             hint: "fields.#{path.join('.')}.source: \"…\"")
      end

      def warn_variant(path, options, first)
        names = options.map(&:ref_name).compact.join(', ')
        warn(:one_of_first_variant, "#{path.join('.')}: #{options.size} variants (#{names}); " \
                                    "first (#{first.ref_name || 'inline'}) is used",
             hint: "fields.#{path.join('.')}.variant: <SchemaName>  (overrides.yml, not implemented yet)")
      end

      def warn_conditional(path, match)
        name = path.join('.')
        warn(:conditional_required, "#{name}: required only for #{match[:field]}=#{match[:value]} (from description)",
             hint: "fields.#{name}.required_if: { field: #{match[:field]}, equals: #{match[:value]} }  applied; verify")
      end

      def info_credential(path)
        info(:credential_field, "#{path.join('.')} → credentials.#{path.last}", hint: 'fill it in credentials')
      end

      private

      def dict = rules.fetch(:field_aliases)
      def amount_expr = findings[:amount]&.value&.[](:expr) || 'operation.amount'

      def requisite_types(request)
        enum = request.find { |m| m.source_expr == 'requisite_type' }&.schema&.enum
        return enum.map(&:to_s) if enum

        request.filter_map(&:requisite_type).uniq
      end

      def headers(endpoint)
        return [] unless endpoint

        endpoint.parameters.select { |p| p.location == 'header' }.filter_map do |param|
          _n, rule = dict['aliases'].find { |_a, r| FieldWalker.match?(r['names'], [param.name]) }
          rule && FieldMapping.new(provider_field: param.name, path: [param.name], source_expr: rule['expr'],
                                   required: param.required, required_if: nil, transform: nil, schema: param.schema,
                                   confidence: 0.9, requisite_type: nil)
        end
      end

      # Внешний или циклический $ref: в схеме запроса create — фатально (D-05, D-14); в ответах — UNSUPPORTED/INFO.
      def check_external_refs(create, schema)
        path, ref = unresolved(schema).first
        raise_unresolved(create, path, ref) if ref
        check_circular(create, schema)
        (spec.endpoints + spec.webhooks).each { |ep| external_in_responses(ep) }
      end

      def raise_unresolved(create, path, ref)
        pointer = "#{create.pointer}/requestBody/#{path.join('/')}"
        if ref.start_with?('#/')
          raise SpecError.new("unresolved $ref '#{ref}' in the create request schema",
                              pointer: pointer, file: spec.source_path, hint: HINT_MISSING)
        end
        message = "external $ref '#{ref}' in the create request schema (#{path.join('.')})"
        raise UnsupportedError.new(message, pointer: pointer, file: spec.source_path, hint: HINT_EXTERNAL)
      end

      def check_circular(create, schema)
        path, chain = circular(schema).first
        return unless chain

        raise SpecError.new("circular $ref: #{chain}", pointer: "#{create.pointer}/requestBody/#{path.join('/')}",
                                                       file: spec.source_path, hint: HINT_CYCLE)
      end

      def circular(schema, prefix = [])
        return [] unless schema
        return [[prefix, schema.circular_ref]] if schema.circular_ref

        children = schema.properties.to_h.map { |n, p| [prefix + [n], p] } + [[prefix + ['[]'], schema.items]]
        children += (schema.one_of.to_a + schema.any_of.to_a).map { |v| [prefix, v] }
        children.flat_map { |pre, child| circular(child, pre) }
      end

      def external_in_responses(endpoint)
        refs = endpoint.responses.flat_map { |r| unresolved(r.schema) }
        return if refs.empty?

        places = refs.map { |path, ref| "#{path.join('.')} → #{ref}" }.uniq.join(', ')
        unsupported(:external_ref, "#{endpoint.method.upcase} #{endpoint.path}: external $ref → {} (#{places})",
                    pointer: endpoint.pointer, hint: 'inline the schema if this response matters')
      end

      def unresolved(schema, prefix = [])
        return [] unless schema
        return [[prefix, schema.unresolved_ref]] if schema.unresolved_ref

        schema.properties.to_h.flat_map do |n, p|
          unresolved(p, prefix + [n])
        end + unresolved(schema.items, prefix + ['[]'])
      end

      def mean(request) = (request.sum(&:confidence) / request.size).round(2)
    end
  end
end
