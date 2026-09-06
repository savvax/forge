# frozen_string_literal: true

module Forge
  # Строки секции анализа для Report (одна строка на finding, в формате ТЗ).
  class ReportLines
    ROLES = %i[create status cancel webhook balance].freeze
    HELPERS = { cancel: 'cancel_request', balance: 'fetch_balance' }.freeze
    WIDTH = 100

    def initialize(spec, findings)
      @spec = spec
      @f = findings
    end

    def header = "Parsing spec... ok (openapi #{@spec.openapi_version}, #{@spec.title} #{@spec.version})"

    def endpoints
      list = @spec.endpoints.map { |e| "#{e.method.upcase} #{e.path}" }
      [wrap("Found #{list.size} endpoints: ", list.join(', '), ',')] + endpoint_rows.map { |row| role_line(row) }
    end

    def endpoint_rows
      roles = @f[:endpoint_roles].value
      ROLES.filter_map do |role|
        ep = roles[role]
        next unless ep

        { role: role, method: ep.method.upcase, path: ep.path, operation_id: ep.operation_id,
          confidence: roles[:confidences][role], outside_contract: HELPERS.key?(role) }
      end
    end

    def auth
      a = @f[:auth].value
      return 'Auth: not found (credentials required; see warnings)' if a[:type] == 'none'

      where = a[:header] ? "header: #{a[:header]}" : "#{a[:location]}: #{a[:param_name]}"
      "Auth: #{a[:scheme_name]} (#{a[:type]}, #{where}) → credentials.#{a[:credential_keys].join('/')}"
    end

    def statuses
      s = @f[:statuses].value
      groups = %w[in_progress approved rejected].filter_map do |internal|
        keys = s[:map].select { |_k, v| v == internal }.keys
        "#{keys.join(', ')} → #{internal}" unless keys.empty?
      end
      groups << "unmapped: #{s[:unmapped].join(', ')}" unless s[:unmapped].empty?
      "Statuses (#{s[:field_path].join('.')}): #{groups.empty? ? 'not found' : groups.join('; ')}"
    end

    def errors
      rows = @f[:errors].value[:rows]
      return 'Errors: none described' if rows.empty?

      dup = rows.map { |r| r[:status] }.tally
      parts = rows.sort_by { |r| [r[:status], ROLES.index(r[:role])] }.map { |r| error_part(r, dup[r[:status]] > 1) }
      wrap('Errors: ', parts.join('; '), ';')
    end

    def webhook_signature
      w = @f[:webhooks].value
      return 'Webhook signature: no webhook found' unless w[:endpoint]

      sig = w[:signature]
      return 'Webhook signature: not found (callbacks are not verified)' unless sig[:header]

      "Webhook signature: #{sig[:header]} (HMAC-#{sig[:algorithm].upcase}, #{sig[:payload].tr('_', ' ')}, " \
        "#{sig[:encoding]}) → credentials.#{sig[:secret_key]}"
    end

    def webhook_events
      w = @f[:webhooks].value
      return nil unless w[:endpoint]

      if w[:event_map].empty?
        from = w[:status_field] ? "status from #{w[:status_field].join('.')}" : 'no known event values or status field'
        return "Webhook events: #{w[:event_field] || 'no event field'} → #{from}"
      end

      "Webhook events: #{w[:event_map].map { |e, s| "#{e} → #{s}" }.join('; ')}"
    end

    def amount
      a = @f[:amount].value
      return 'Amount: field not found' unless a[:field]

      min = a[:minimum_major] ? ", min #{a[:minimum_major]} #{a[:currencies].first}".rstrip : ''
      "Amount: #{a[:type]}, #{a[:unit]} units (×#{a[:multiplier]})#{min} — source: #{@f[:amount].source}"
    end

    def fields
      v = @f[:fields].value
      unmapped = v[:request].count { |m| m.source_expr.nil? }
      types = v[:requisite_types].empty? ? '' : " (#{v[:requisite_container]}: #{v[:requisite_types].join(', ')})"
      "Fields: #{v[:request].size} request fields, #{unmapped} unmapped#{types}"
    end

    private

    def role_line(row)
      note = row[:outside_contract] ? "   (outside contract → #{HELPERS[row[:role]]})" : ''
      values = { role: row[:role], endpoint: "#{row[:method]} #{row[:path]}", id: row[:operation_id],
                 conf: row[:confidence], note: note }
      format('  %<role>-8s %<endpoint>-42s %<id>-24s confidence %<conf>.2f%<note>s', values)
    end

    def error_part(row, ambiguous)
      role = ambiguous ? " (#{row[:role]})" : ''
      retry_after = row[:action] == 'retry_backoff' && @f[:errors].value[:retry_after_header]
      code = row[:provider_code] || row[:internal_code]
      "#{row[:status]}#{role} #{code} → #{row[:action]}#{" (#{retry_after})" if retry_after}"
    end

    # Перенос длинной строки после разделителя с отступом по ширине префикса.
    def wrap(prefix, text, separator)
      indent = ' ' * prefix.size
      lines = [+prefix]
      text.split("#{separator} ").each_with_index do |part, i|
        chunk = i.zero? ? part : "#{separator} #{part}"
        if lines.last.size + chunk.size > WIDTH
          lines.last << separator
          lines << "#{indent}#{part}"
        else
          lines.last << chunk
        end
      end
      lines.join("\n")
    end
  end
end
