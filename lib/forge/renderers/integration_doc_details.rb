# frozen_string_literal: true

module Forge
  module Renderers
    # INTEGRATION.md, вводные разделы: «Кратко», «Как платформа работает с сервисом», ключи настройки.
    # Только данные IntegrationPlan; формулировки — русский текст, идентификаторы — как в коде.
    module IntegrationDocDetails
      def summary_lines
        [provider_line, service_line, api_line, status_line,
         "- Заполнить вручную: #{credential_keys.uniq.map { |k| "`credentials.#{k}`" }.join(', ')}; " \
         'все допущения анализа — в разделе «Допущения».']
      end

      def provider_line
        "- Провайдер: **#{plan.provider[:title]}**; спецификация #{plan.meta[:spec_title]} " \
          "#{plan.meta[:spec_version]} (`#{plan.meta[:spec_file]}`)."
      end

      def service_line
        "- Сервис: `Provider::#{plan.provider[:class_name]}` (`#{plan.provider[:file_name]}`) реализует контракт " \
          '`Provider::BaseService`: `check_conditions`, `create_request`, `fetch_status`, `process_callback`.'
      end

      def api_line
        prod = plan.base_url[:production]
        note = prod && prod != plan.base_url[:default] ? ", production `#{prod}`" : ''
        "- API: `#{plan.base_url[:default]}` (sandbox по умолчанию)#{note}; авторизация — #{auth_name}."
      end

      def status_line
        "- Выплата создаётся `#{op_label(plan.operations[:create])}`, статус — #{status_sources}; итог операции — " \
          '`in_progress` / `approved` / `rejected`.'
      end

      def op_label(oper) = oper ? "#{oper.method.upcase} #{oper.path}" : '—'

      def status_sources
        parts = []
        parts << "`#{op_label(plan.operations[:status])}`" if plan.operations[:status]
        parts << "webhook `POST #{plan.webhook[:endpoint].path}`" if plan.webhook
        parts.empty? ? 'в спеке не описан (см. «Допущения»)' : parts.join(' и ')
      end

      def flow_lines
        [check_conditions_line, create_request_line,
         "- `fetch_status(operation)` — #{fetch_status_line}.",
         "- `process_callback(payload, raw_body:, headers:)` — #{callback_line}.",
         '- Ошибки провайдера → `failure` по таблице «Обработка ошибок» (семантика действий — там же).']
      end

      def check_conditions_line
        types = plan.requisite_types.map { |t| "`#{t}`" }.join(', ')
        kinds = types.empty? ? 'платёжный метод шлюза (реквизитов по типам в схеме нет)' : "тип реквизитов (#{types})"
        '- `check_conditions(operation, request_method)` — предпроверки до запроса (раздел «Проверки перед ' \
          "отправкой»); `request_method` — #{kinds} либо служебное `status` / `check`."
      end

      def create_request_line
        create = plan.operations[:create]
        '- `create_request(operation, request_method)` — собирает тело по таблице «Поля запроса» и шлёт ' \
          "`#{op_label(create)}`; успех — HTTP #{create.success_statuses.join(', ')}; id выплаты сохраняется в " \
          "`operation.provider_operation_key` из `#{create.response_id_path.to_a.join('.')}`. " \
          '`request_method` `status`/`check` делегируется в `fetch_status`.'
      end

      def fetch_status_line
        oper = plan.operations[:status]
        return '`failure(:not_implemented, "status_endpoint_missing")`: status-эндпоинта в спеке нет' unless oper

        "`#{op_label(oper)}`, статус из `#{oper.response_status_path.to_a.join('.')}` по «Маппингу статусов»"
      end

      def callback_line
        w = plan.webhook
        return '`failure(:not_implemented, "callbacks_not_supported")`: webhook в спеке нет' unless w

        sig = w[:signature][:header] ? "проверяет подпись `#{w[:signature][:header]}`, " : ''
        status = "статус из `#{w[:status_field].to_a.join('.')}`"
        key = w[:event_map].empty? ? status : "событие из `#{w[:event_field]}`"
        "#{sig}берёт #{key}, находит операцию по `#{w[:id_field].to_a.join('.')}` и переводит её в " \
          'approved / rejected / in_progress'
      end

      def settings_rows
        rows = [["ENV `#{plan.base_url[:env_var]}`", "базовый URL; по умолчанию sandbox `#{plan.base_url[:default]}`"]]
        if plan.auth[:type] == 'oauth2'
          rows << ["ENV `#{plan.provider[:env_prefix]}_TOKEN_URL`",
                   "адрес токена OAuth2; по умолчанию `#{plan.auth[:token_url]}`"]
        end
        rows += auth_credential_rows + field_credential_rows
        rows << ['`config.callback_url`', 'адрес приёма webhook на стороне Space Payments']
        rows.map { |key, note| "| #{key} | #{note} |" }
      end

      def auth_credential_rows
        rows = plan.auth[:credential_keys].to_a.map do |k|
          ["`credentials.#{k}`", "авторизация (#{auth_name}), выдаёт провайдер"]
        end
        return rows unless plan.webhook&.dig(:signature, :header)

        rows << ["`credentials.#{plan.webhook[:signature][:secret_key]}`", 'секрет подписи webhook, выдаёт провайдер']
      end

      def field_credential_rows
        rows = plan.fields[:request].filter_map do |m|
          key = m.source_expr&.[](/credentials\.fetch\('(\w+)'\)/, 1)
          key && ["`credentials.#{key}`", "поле запроса `#{m.path.join('.')}`"]
        end
        rows + path_credential_params.map { |p| ["`credentials.#{p}`", 'идентификатор подключения в пути запроса'] }
      end
    end
  end
end
