# frozen_string_literal: true

require 'json'

module Forge
  module Renderers
    # INTEGRATION.md, подробные разделы: методы с примерами из фикстур, сумма, реквизиты, предпроверки,
    # приём webhook, семантика ошибок, файлы. Только данные IntegrationPlan.
    module IntegrationDocSections
      RULE_TEXT = { min: '≥ %s', max: '≤ %s', enum: 'один из: %s', max_length: 'длина ≤ %s',
                    min_length: 'длина ≥ %s', pattern: 'формат `%s`' }.freeze
      SOURCES = { paths: 'эндпоинт в `paths`', callbacks: '`callbacks` эндпоинта создания',
                  webhooks: 'top-level `webhooks` спеки' }.freeze
      def json(obj) = JSON.pretty_generate(obj)

      def operation_sections
        %i[create status].filter_map { |role| plan.operations[role] && operation_section(role, plan.operations[role]) }
      end

      def operation_section(role, oper)
        fx = plan.fixtures[role == :create ? 'create_request' : 'fetch_status'] || {}
        ok = oper.success_statuses.first
        examples = [['Пример запроса', fx['request']], ["Пример ответа #{ok}", fx["response_#{ok}"]]]
        { title: "#{IntegrationDoc::METHOD_ROWS[role][0]} — #{op_label(oper)}", lines: operation_lines(role, oper),
          examples: examples.select { |_, v| v } }
      end

      def operation_lines(role, oper)
        replay = oper.success_statuses.include?(409) ? ' (409 — повтор по Idempotency-Key, читается как успех)' : ''
        lines = ["- Успех: HTTP #{oper.success_statuses.join(', ')}#{replay}; id выплаты — " \
                 "`#{oper.response_id_path.to_a.join('.')}`, статус — #{path_or_missing(oper.response_status_path)}."]
        lines << request_line(role, oper)
        unless oper.error_statuses.empty?
          lines << "- Ошибки: HTTP #{oper.error_statuses.join(', ')} — см. «Обработка ошибок»."
        end
        lines.compact
      end

      def path_or_missing(path) = path.to_a.empty? ? 'в ответе не найден (см. «Допущения»)' : "`#{path.join('.')}`"

      def request_line(role, oper)
        if role == :create
          idem = oper.headers.first
          headers = idem ? " и `#{idem.provider_field}: #{idem.source_expr}`" : ''
          "- Тело: #{oper.body_encoding}; заголовки: авторизация#{headers}."
        elsif oper.status_request_field
          "- Тело: `{ \"#{oper.status_request_field}\": operation.provider_operation_key }` (id выплаты в теле)."
        end
      end

      def amount_lines
        a = plan.amount
        return ['Поле суммы в схеме запроса не найдено — см. «Допущения» и `fields.<path>.source`.'] unless a[:field]

        unit = a[:unit] == :minor ? "минорные единицы (×#{a[:multiplier]})" : 'мажорные единицы'
        lines = ["- Поле `#{a[:path].join('.')}` (#{a[:type]}): #{unit} — `#{a[:expr]}`."]
        lines << "- Минимум: #{a[:minimum_major]} (`check_conditions` → `amount_too_low`)." if a[:minimum_major]
        lines << "- Максимум: #{a[:maximum_major]} (`amount_too_high`)." if a[:maximum_major]
        lines << "- Валюты: #{currencies_note(a)}"
      end

      def currencies_note(amount)
        list = amount[:currencies].empty? ? 'в спеке не перечислены' : amount[:currencies].join(', ')
        return "#{list}." unless amount[:currency_field]

        "#{list}; поле `#{amount[:currency_field]}`, иная валюта → `currency_not_supported`."
      end

      def requisite_rows
        plan.requisite_types.map do |type|
          cells = plan.fields[:request].select { |m| requisite_of?(m, type) }
                                       .map { |m| "`#{m.path.last}` (#{requirement(m)})" }
          "| #{type} | #{cells.empty? ? '—' : cells.join(', ')} |"
        end
      end

      def requisite_of?(mapping, type)
        expr = mapping.source_expr.to_s
        mapping.requisite_type == type || expr.include?("dig('#{type}'") || expr.include?('dig(requisite_type')
      end

      def validation_rows
        plan.validations.map do |v|
          value = v[:value].is_a?(Array) ? v[:value].join(', ') : v[:value]
          scope = v[:requisite_type] ? " (тип `#{v[:requisite_type]}`)" : ''
          "| #{v[:field]} | #{format(RULE_TEXT.fetch(v[:rule], '%s'), value)}#{scope} | #{v[:error_code]} |"
        end
      end

      def webhook_lines
        w = plan.webhook
        ["- Эндпоинт провайдера: `POST #{w[:endpoint].path}` (источник: #{SOURCES.fetch(w[:source], w[:source])}).",
         '- Адрес приёма на стороне Space Payments — `config.callback_url`; его нужно зарегистрировать у провайдера.',
         "- Поле события: #{w[:event_field] ? "`#{w[:event_field]}`" : 'нет'}; поле статуса: " \
         "#{path_or_missing(w[:status_field])}; id выплаты: #{path_or_missing(w[:id_field])}.",
         '- Повторная доставка того же события безопасна: переход в тот же статус идемпотентен.',
         '- Проверка на моке: `POST /_simulate/<id>/<event>` — мок шлёт подписанный webhook на `WEBHOOK_URL`.']
      end

      def callback_examples
        %w[callback callback_failed].filter_map do |key|
          fx = plan.fixtures[key]
          label = key == 'callback' ? 'Успешное' : 'Неуспешное'
          fx && ["#{label} событие → `#{fx['expected_operation_status']}`", fx['payload']]
        end
      end

      def file_rows
        name = plan.provider[:name]
        rows = IntegrationDoc::FILES.map { |file, note| [format(file, name), format(note, plan.provider[:class_name])] }
        if plan.outside_contract.any? { |o| o[:helper] }
          rows << ["#{name}_extras.rb", 'хелперы вне контракта (`cancel_request`, `fetch_balance`)']
        end
        rows.map { |file, note| "| `#{file}` | #{note} |" }
      end
    end
  end
end
