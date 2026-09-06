# frozen_string_literal: true

module Forge
  module Plan
    # Правки отдельных findings по ключам overrides (statuses, events, webhook, amount, fields, auth, errors).
    class OverridesEdits
      def initialize(overrides, log)
        @o = overrides
        @log = log
      end

      def statuses(findings)
        finding = findings[:statuses]
        map = finding.value[:map].dup
        @o['statuses'].to_h.each do |raw, internal|
          map[raw.to_s] = internal.to_s
          @log.close(:unmapped_status, "'#{raw}'")
          @log.close(:unmapped_event, "status '#{Rules.normalize(raw)}'")
          @log.applied("statuses.#{raw}", internal)
        end
        finding.with(value: finding.value.merge(map: map, unmapped: finding.value[:unmapped] - map.keys))
      end

      def webhooks(findings)
        finding = findings[:webhooks]
        value = finding.value.dup
        value[:event_map] = value[:event_map].merge(events_from_statuses(findings, value)) { |_k, old, _new| old }
        @o['events'].to_h.each do |event, internal|
          value[:event_map] = value[:event_map].merge(event.to_s => internal.to_s)
          @log.close(:unmapped_event, "'#{event}'")
          @log.applied("events.#{event}", internal)
        end
        webhook_keys(value)
        finding.with(value: value)
      end

      def amount(findings)
        finding = findings[:amount]
        a = @o['amount'].to_h
        return finding if a.empty?

        value = finding.value.merge(a.slice('multiplier', 'minimum_major').transform_keys(&:to_sym))
        value[:unit] = a['unit'].to_sym if a['unit']
        value[:expr] = value[:unit] == :minor ? 'to_minor_units(operation.amount)' : 'operation.amount'
        @log.close(:amount_unit_assumed, nil)
        @log.applied('amount', a.keys.join(', '))
        finding.with(value: value)
      end

      def fields(findings)
        finding = findings[:fields]
        request = finding.value[:request].map { |m| field(m, @o['fields'].to_h[m.path.join('.')]) }
        finding.with(value: finding.value.merge(request: request))
      end

      def auth(findings)
        finding = findings[:auth]
        a = @o['auth'].to_h
        return finding if a.empty?

        value = finding.value.merge(a.transform_keys(&:to_sym))
        value[:credential_keys] = [value[:credential_key]] if a['credential_key']
        @log.close(:auth_not_found, nil)
        @log.close(:api_key_in_query, nil)
        @log.applied('auth', a.keys.join(', '))
        finding.with(value: value)
      end

      def errors(findings)
        finding = findings[:errors]
        e = @o['errors'].to_h
        return finding if e.empty?

        rows = finding.value[:rows].map { |row| error_row(row, e) }
        e.each { |key, rule| @log.applied("errors.#{key}", rule.to_h.values.join('/')) }
        finding.with(value: finding.value.merge(rows: rows, http: http_map(rows)))
      end

      private

      # statuses.X закрывает и события, чей суффикс = X (transfer.on_hold → ON_HOLD).
      def events_from_statuses(findings, value)
        map = findings[:statuses].value[:map]
        event_enum(value).each_with_object({}) do |event, acc|
          suffix = Analyzers::Webhooks.event_status(event, rules)
          match = map.find { |raw, _| Rules.normalize(raw) == suffix }
          acc[event] = match[1] if match
        end
      end

      def event_enum(value)
        body = value[:endpoint]&.request_body
        property = body && value[:event_field] && body.schema&.properties.to_h[value[:event_field]]
        Array(property&.enum).map(&:to_s)
      end

      def rules = @rules ||= Rules.load

      def webhook_keys(value)
        w = @o['webhook'].to_h
        return if w.empty?

        value[:signature] = value[:signature].dup
        w.each { |key, val| webhook_key(value, key, val.to_s) }
        @log.applied('webhook', w.keys.join(', '))
      end

      def webhook_key(value, key, val)
        case key
        when /\Asignature_(\w+)\z/ then value[:signature][::Regexp.last_match(1).to_sym] = val
        when 'event_field' then value[:event_field] = val
        else value[key.to_sym] = val.split('.')
        end
        @log.close(:"#{key}_assumed", nil)
        @log.close(:signature_not_found, nil) if key == 'signature_header'
        @log.close(:signature_timestamped, nil) if key == 'signature_scheme'
      end

      def field(mapping, rules)
        return mapping if rules.nil?

        name = mapping.path.join('.')
        mapping = mapping.with(source_expr: rules['source'].to_s, confidence: 1.0) if rules.key?('source')
        mapping = mapping.with(required: rules['required'] == true) if rules.key?('required')
        if rules.key?('required_if')
          mapping = mapping.with(required_if: condition(rules['required_if']),
                                 confidence: 1.0)
        end
        [[:unmapped_field, "#{name} "], [:array_field_unsupported, "#{name} "], [:conditional_required, "#{name}:"],
         [:one_of_first_variant, "#{name}:"]]
          .each { |code, frag| @log.close(code, frag) }
        @log.applied("fields.#{name}", rules.keys.join(', '))
        mapping
      end

      def condition(hash) = { field: hash.to_h['field'].to_s, equals: hash.to_h['equals'].to_s }

      def error_row(row, overrides)
        rule = overrides[row[:status]] || overrides[row[:status].to_s] || overrides[row[:provider_code]]
        return row unless rule.is_a?(Hash)

        @log.close(:duplicate_as_success, "HTTP #{row[:status]}")
        row.merge(rule.transform_keys(&:to_sym).slice(:action, :internal_code).transform_values(&:to_s))
      end

      def http_map(rows)
        rows.reject { |r| r[:action] == 'treat_as_success' || r[:role] == :cancel }.sort_by { |r| r[:status] }
            .each_with_object({}) { |r, acc| acc[r[:status]] ||= r[:internal_code] }
      end
    end
  end
end
