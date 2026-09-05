# frozen_string_literal: true

require 'json'

module Forge
  module Web
    # Данные обзорной панели из report.json: роли, auth, статусы, ошибки, webhook, сумма, поля, предупреждения.
    class Overview
      ROLE_TITLES = { 'create' => 'Создание выплаты', 'status' => 'Статус', 'cancel' => 'Отмена',
                      'webhook' => 'Webhook', 'balance' => 'Баланс' }.freeze

      def self.from(json) = new(JSON.parse(json))

      def initialize(data)
        @d = data
      end

      def spec = @d['spec'] || {}
      def endpoints = (@d['endpoints'] || []).map { |e| e.merge('title' => ROLE_TITLES[e['role']]) }
      def auth = @d['auth'] || {}
      def statuses = @d['statuses'] || {}
      def errors = (@d.dig('errors', 'rows') || []).sort_by { |r| [r['status'], r['role']] }
      def webhook = @d['webhook'] || {}
      def amount = @d['amount'] || {}
      def fields = @d.dig('fields', 'request') || []
      def warnings = (@d['warnings'] || []).group_by { |w| w['level'] }
      def exit_code = @d['exit_code']

      def confidence_class(value)
        return 'ok' if value.to_f >= 0.8
        return 'warn' if value.to_f >= 0.5

        'err'
      end

      def status_groups
        map = statuses['map'] || {}
        %w[in_progress approved rejected].map { |internal| [internal, map.select { |_k, v| v == internal }.keys] }
      end

      def auth_line
        case auth['type']
        when 'api_key' then "API key · #{auth['location']} `#{auth['header'] || auth['param_name']}` → api_key"
        when 'bearer' then 'Bearer token · Authorization → credentials.token'
        when 'basic' then 'Basic auth · Authorization → credentials.login / password'
        else 'не найдена (см. предупреждения)'
        end
      end

      def signature_line
        sig = webhook['signature'] || {}
        return 'нет' unless sig['header']

        algo = "HMAC-#{sig['algorithm'].to_s.upcase}"
        "#{sig['header']} · #{algo} · #{sig['payload']} · #{sig['encoding']} → credentials.#{sig['secret_key']}"
      end

      def amount_line
        return 'поле суммы не найдено' unless amount['field']

        unit = amount['unit'] == 'minor' ? "минорные единицы ×#{amount['multiplier']}" : 'мажорные единицы'
        min = amount['minimum_major'] ? ", минимум #{amount['minimum_major']}" : ''
        currencies = Array(amount['currencies']).join(', ')
        "#{amount['path'].to_a.join('.')} (#{amount['type']}) · #{unit}#{min} · валюты: #{currencies}"
      end
    end
  end
end
