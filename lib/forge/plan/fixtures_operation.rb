# frozen_string_literal: true

module Forge
  module Plan
    # Обратное отображение примера запроса в Provider::Operation по FieldMapping (для fixtures.json).
    class FixturesOperation
      REQUISITE_EXPR = /\Aoperation\.payout_requisite\.dig\((.+?), '(.+?)'\)\z/

      def initialize(findings)
        @f = findings
      end

      # Обратное отображение примера запроса в Provider::Operation по FieldMapping.
      # → [operation, extras]; extras: credentials / config, найденные в примере.
      def from(request)
        @extras = {}
        op = { 'id' => nil, 'amount' => nil, 'currency' => nil, 'payout_requisite' => {} }
        type = canonical_type_of(request)
        @f[:fields].value[:request].each do |m|
          value = dig(request, m.path)
          assign(op, m, value, type) unless value.nil?
        end
        [with_defaults(op).compact, @extras]
      end

      # Чего нет в примере: реквизиты типа по умолчанию, минимальная сумма, первая валюта (BaseService требует их).
      def with_defaults(operation)
        operation['payout_requisite'] = { default_type => {} } if operation['payout_requisite'].empty?
        fill_requisite_defaults(operation['payout_requisite'])
        operation['amount'] ||= format('%.2f', @f[:amount].value[:minimum_major] || 1)
        operation['currency'] ||= @f[:amount].value[:currencies].first || 'USD'
        operation
      end

      def canonical_type_of(request)
        raw = dig(request, @f[:fields].value[:request].find { |m| m.source_expr == 'requisite_type' }&.path)
        raw && (@f[:fields].value[:requisite_type_values].to_h.key(raw.to_s) || raw)
      end

      def default_type = @f[:fields].value[:requisite_types].first || 'default'

      # Канонические поля типа (CONTRACT § 3), которых нет в примере: чтобы override-выражения имели данные.
      def fill_requisite_defaults(requisites)
        defaults = Rules.load.fetch(:field_aliases)['requisite_defaults'].to_h
        requisites.each do |type, fields|
          defaults.fetch(type, {}).each { |key, value| fields[key] = value unless fields.key?(key) }
        end
      end

      def assign(operation, mapping, value, type)
        case mapping.source_expr
        when 'operation.id.to_s' then operation['id'] = value.to_s
        when 'operation.currency' then operation['currency'] = value.to_s
        when /\Aoperation\.description/ then operation['description'] = value.to_s
        when /\Aoperation\.customer&\.dig\('(\w+)'\)/ then (operation['customer'] ||= {})[::Regexp.last_match(1)] =
                                                             value
        when REQUISITE_EXPR then assign_requisite(operation, type, value, ::Regexp.last_match)
        else assign_extra(operation, mapping, value)
        end
      end

      # credentials.fetch('merchant_id') / callback_url — не часть Operation, кладутся рядом в create_request.
      def assign_extra(operation, mapping, value)
        case mapping.source_expr
        when /credentials\.fetch\('(\w+)'\)/ then (@extras['credentials'] ||= {})[::Regexp.last_match(1)] = value
        when 'callback_url' then @extras['config'] = { 'callback_url' => value }
        else operation['amount'] = major_amount(value) if mapping.transform == 'amount'
        end
      end

      def assign_requisite(operation, type, value, match)
        key = match[1].delete("'")
        key = type if key == 'requisite_type'
        (operation['payout_requisite'][key] ||= {})[match[2]] = value if key
      end

      def major_amount(value)
        amount = @f[:amount].value
        number = amount[:unit] == :minor ? value.to_r / amount[:multiplier] : value.to_r
        number = amount[:minimum_major] || 1 unless number.positive? # синтез без примера → минимально валидная сумма
        format('%.2f', number)
      end

      private

      def dig(node, path) = path.to_a.reduce(node) { |cur, key| cur.is_a?(Hash) ? cur[key] : nil }
    end
  end
end
