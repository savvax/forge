# frozen_string_literal: true

module Forge
  module Renderers
    # Строки build_payout_payload / build_recipient из FieldMapping плана.
    class ServicePayload
      TODO = "# TODO(forge): map '%s' (see overrides.yml)"
      DIG = /operation\.payout_requisite\.dig\((?:'[^']+'|requisite_type), '([^']+)'\)/

      def initialize(plan)
        @plan = plan
        @container = plan.fields[:requisite_container]&.split('.')
      end

      def container? = !@container.nil?

      # Варианты по типам: есть поле типа или несколько типов реквизитов.
      def variants? = container? && (!type_field.nil? || @plan.requisite_types.size > 1)

      def payload_lines
        lines = tree(@plan.fields[:request].reject { |m| inside_container?(m) }, [])
        return lines unless container?

        lines[-1] = "#{lines.last}," unless lines.empty? || lines.last.include?('# TODO')
        lines << "#{@container.first}: build_recipient(operation, requisite_type)"
      end

      def recipient_lines
        return variant_lines if variants?

        tree(@plan.fields[:request].select { |m| inside_container?(m) }, @container, requisite: true)
      end

      private

      def type_field = @plan.fields[:request].find { |m| m.source_expr == 'requisite_type' }
      def inside_container?(mapping) = container? && mapping.path.first(@container.size) == @container
      def requisite_expr(mapping) = mapping.source_expr.gsub(DIG, "requisite['\\1']")

      # Вложенные объекты → многострочный hash; листья → `key: expr,` (последний без запятой).
      def tree(mappings, prefix, requisite: false)
        entries = mappings.group_by { |m| m.path[prefix.size] }.map do |key, group|
          leaf = group.find { |m| m.path == prefix + [key] }
          next leaf_entry(key, leaf, requisite) if leaf

          [["#{key}: {", *tree(group, prefix + [key], requisite: requisite).map { |l| "  #{l}" }, '}']]
        end
        with_commas(entries)
      end

      def leaf_entry(key, mapping, requisite)
        return ["#{key}: nil, #{format(TODO, mapping.path.join('.'))}", :todo] if mapping.source_expr.nil?

        [["#{key}: #{requisite ? requisite_expr(mapping) : mapping.source_expr}"]]
      end

      def with_commas(entries)
        entries.flat_map.with_index do |(lines, kind), index|
          next lines if kind == :todo || index == entries.size - 1

          lines[0..-2] + ["#{lines.last},"]
        end
      end

      def variant_lines
        inner = @plan.fields[:request].select { |m| inside_container?(m) }
        base, typed = inner.partition { |m| m.requisite_type.nil? && m.required_if.nil? }
        lines = ['requisite = operation.payout_requisite.fetch(requisite_type)',
                 "base = { #{base.map { |m| base_entry(m) }.join(', ')} }"]
        lines + (typed.empty? ? ['base'] : case_lines(typed.group_by(&:requisite_type)))
      end

      def case_lines(typed)
        ['case requisite_type', *typed.map { |type, mappings| variant_line(type, mappings) }, 'else base', 'end']
      end

      def base_entry(mapping)
        return "#{mapping.provider_field}: requisite_type" if mapping.source_expr == 'requisite_type'

        "#{mapping.provider_field}: #{requisite_expr(mapping)}"
      end

      def variant_line(type, mappings)
        merged = mappings.map { |m| "#{m.provider_field}: #{requisite_expr(m)}" }.join(', ')
        notes = mappings.select(&:required_if).map do |m|
          "#{m.provider_field} required for #{m.required_if[:field]}=#{m.required_if[:equals]} (from description)"
        end
        "when '#{type}' then base.merge(#{merged}).compact#{" # #{notes.join('; ')}" unless notes.empty?}"
      end
    end
  end
end
