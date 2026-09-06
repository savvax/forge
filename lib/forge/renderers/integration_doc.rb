# frozen_string_literal: true

require_relative 'base'

module Forge
  module Renderers
    # INTEGRATION.md по templates/integration.md.erb (docs/OUTPUT_FORMAT.md § 3).
    class IntegrationDoc < Base
      AUTH_NAMES = { 'api_key' => 'API Key', 'bearer' => 'Bearer token', 'basic' => 'Basic auth',
                     'none' => 'не найдена' }.freeze
      ACTIONS = { 'reject' => 'reject', 'alert_block' => 'alert ops, block provider', 'retry' => 'retry later',
                  'retry_backoff' => 'retry with backoff', 'alert' => 'alert ops',
                  'treat_as_success' => 'treat as success (idempotent replay)' }.freeze
      METHOD_ROWS = { create: ['create_payout', 'Создание выплаты'], status: %w[get_status Статус],
                      cancel: %w[cancel Отмена], balance: %w[balance Баланс] }.freeze

      def template_name = 'integration.md.erb'
      def filename = 'INTEGRATION.md'

      private

      def auth_name = AUTH_NAMES.fetch(plan.auth[:type], plan.auth[:type])

      def auth_header
        case plan.auth[:type]
        when 'api_key' then api_key_header(plan.auth)
        when 'bearer' then '`Authorization: Bearer <credentials.token>`'
        when 'basic' then '`Authorization: Basic base64(<credentials.login>:<credentials.password>)`'
        else '—'
        end
      end

      def api_key_header(auth)
        return "`#{auth[:header]}: <credentials.api_key>`" if auth[:header]

        "query `#{auth[:param_name]}=<credentials.api_key>`"
      end

      def credential_keys
        keys = plan.auth[:credential_keys].to_a.dup
        keys << plan.webhook[:signature][:secret_key] if plan.webhook&.dig(:signature, :header)
        keys += plan.fields[:request].filter_map { |m| m.source_expr&.[](/credentials\.fetch\('(\w+)'\)/, 1) }
        keys + path_credential_params
      end

      # ids подключения в пути: все {param} у create, кроме последнего у status/cancel (он — id выплаты).
      def path_credential_params
        %i[create status cancel].flat_map do |role|
          params = plan.operations[role]&.path.to_s.scan(/\{(\w+)\}/).flatten
          role == :create ? params : params[0..-2].to_a
        end.uniq
      end

      def method_rows
        rows = plan.operations.filter_map { |role, oper| oper && method_row(role, oper) }
        return rows unless plan.webhook

        header = plan.webhook[:signature][:header] || '-'
        rows << "| webhook | POST #{plan.webhook[:endpoint].path} | Callback | #{header} |"
      end

      def method_row(role, oper)
        name, purpose = METHOD_ROWS[role]
        header = oper.headers.first
        idempotency = role == :create && header ? "#{header.provider_field} header" : '-'
        "| #{name} | #{oper.method.upcase} #{oper.path.gsub(/\{\w+\}/, '{id}')} | #{purpose} | #{idempotency} |"
      end

      def error_rows
        plan.error_map.map do |status, e|
          action = e[:action] == 'retry' && status >= 500 ? 'retry, alert ops' : ACTIONS.fetch(e[:action], e[:action])
          "| #{status} | #{e[:provider_code] || e[:internal_code]} | #{action} |"
        end
      end

      def signature_line
        sig = plan.webhook[:signature]
        over = sig[:payload] == 'fields' ? 'fields' : 'body'
        line = "HMAC-#{sig[:algorithm].to_s.upcase}(#{over}, #{sig[:secret_key]}) → #{sig[:encoding]} → #{sig[:header]}"
        return line unless sig[:scheme] == 'timestamped'

        "#{line.sub("(#{over},", "(\"<t>.<#{over}>\",")}: `t=<unix timestamp>,v1=<hmac>`"
      end

      def field_rows
        plan.fields[:request].map do |m|
          source = m.source_expr ? "`#{m.source_expr}`" : '**TODO** (overrides.yml)'
          "| #{m.path.join('.')} | #{source} | #{requirement(m)} | #{m.transform || '-'} |"
        end
      end

      def cell(text) = text.to_s.gsub('|', '\\|')

      def requirement(mapping)
        return "если #{mapping.required_if[:field]}=#{mapping.required_if[:equals]}" if mapping.required_if

        mapping.required ? 'да' : 'нет'
      end

      def assumption_rows
        plan.warnings.reject { |w| w.level == :info }.map do |w|
          source = "#{w.code}#{" at `#{w.pointer}`" if w.pointer}"
          "| #{cell(w.message)} | #{cell(source)} | #{w.level.to_s.upcase} | #{w.hint ? "`#{cell(w.hint)}`" : '—'} |"
        end
      end
    end
  end
end
