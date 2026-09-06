# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Роль каждого эндпоинта по очкам сигналов (rules/endpoint_roles.yml, docs/RULES.md § 2).
    class EndpointRoles < Base
      ROLES = %i[create status cancel webhook balance].freeze

      def call
        candidates = endpoints
        check_include_paths(candidates)
        assigned = assign(candidates)
        assigned[:webhook] ||= explicit_webhook
        check_path_params(assigned.compact)
        value = build_value(candidates, assigned.compact)
        check_create(value)
        finding(:endpoint_roles, value, confidence: value[:confidences].fetch(:create, 0.0), source: source_text(value))
      end

      private

      def build_value(candidates, assigned)
        ROLES.to_h { |role| [role, assigned.dig(role, 0)] }
             .merge(other: candidates - assigned.values.map(&:first),
                    confidences: assigned.transform_values(&:last))
      end

      # {role => [endpoint, score]}: каждый эндпоинт — одна роль, каждая роль — один эндпоинт.
      def assign(candidates)
        groups = best_roles(candidates).group_by { |(_endpoint, role, _score)| role }
        create = groups.key?(:create) ? pick_winner(:create, groups.delete(:create)) : nil
        winners = groups.filter_map { |role, group| winner_for(role, group, create) }
        create ? { create: create }.merge(winners.to_h) : winners.to_h
      end

      def winner_for(role, group, create)
        related = group.select { |(endpoint, _role, _score)| related?(endpoint, role, create) }
        winner = related.empty? ? nil : pick_winner(role, related, base: resource_of(create))
        [role, winner] if winner
      end

      # Путь create-эндпоинта без {параметров}: /v2/payouts — ресурс выплат для tie-break и related?.
      def resource_of(create) = create && create[0].path.sub(/\{.*\z/, '')

      # [endpoint, лучшая роль, очки] для кандидатов, прошедших порог warn.
      def best_roles(candidates)
        candidates.filter_map do |endpoint|
          role, score = scores(endpoint).max_by { |_role, points| points }
          [endpoint, role, score] if score && score >= threshold(:warn)
        end
      end

      # status/cancel вне ресурса выплат — шум (GET /static-qr/{id} в спеке без выплат): нужен payout-слово в пути
      # или путь под create-эндпоинтом.
      def related?(endpoint, role, create)
        return true unless %i[status cancel].include?(role)

        facts = Facts.new(endpoint, rules.fetch(:endpoint_roles), weak_ok: weak_ok?)
        facts.payout_path? || (create && endpoint.path.start_with?(resource_of(create)))
      end

      def pick_winner(role, group, base: nil)
        # Равные очки: путь под create-эндпоинтом (/v2/payouts/{id} > /v2/unmatched-credit-transfers/{id}), затем короче
        # путь (каноничнее ресурс: /transfer/create < /transfer/x/y/create), затем порядок в спеке.
        winner, *losers = group.sort_by.with_index do |(ep, _role, score), index|
          [-score, base && ep.path.start_with?(base) ? 0 : 1, ep.path.count('/'), index]
        end
        losers.each { |(endpoint, _role, score)| conflict(endpoint, role, winner, score) }
        return rejected(winner[0], role, winner[2]) if winner[2] < min_confidence(role)

        low_confidence(winner[0], role, winner[2])
        [winner[0], winner[2]]
      end

      # roles.<role>.min_confidence — ниже роль не назначается (webhook: слово в пути + POST ≠ callback).
      def min_confidence(role) = rules.fetch(:endpoint_roles).dig('roles', role.to_s, 'min_confidence') || 0.0

      def rejected(endpoint, role, score)
        message = "#{role}: #{label(endpoint)} scored #{score} (below #{min_confidence(role)}); not used"
        warn(:"#{role}_rejected", message, pointer: endpoint.pointer,
                                           hint: "endpoints.#{name(endpoint)}: #{role}  (overrides.yml) to force it")
        nil
      end

      def scores(endpoint)
        dict = rules.fetch(:endpoint_roles)
        facts = Facts.new(endpoint, dict, weak_ok: weak_ok?)
        dict['roles'].filter_map do |role, cfg|
          [role.to_sym, facts.score(cfg['signals'], role.to_sym)] if facts.requires?(cfg['requires'])
        end
      end

      # Слабые слова (payment) — слова выплаты, только если ни один путь не содержит сильного (payout, transfer…).
      def weak_ok?
        return @weak_ok if defined?(@weak_ok)

        dict = rules.fetch(:endpoint_roles)
        @weak_ok = endpoints.none? { |e| Facts.new(e, dict).strong_payout_path? }
      end

      def explicit_webhook
        endpoint = spec.webhooks.first
        return nil unless endpoint

        info(:"webhook_source_#{endpoint.source}", "webhook taken from #{endpoint.source}: #{label(endpoint)}",
             pointer: endpoint.pointer)
        [endpoint, rules.fetch(:endpoint_roles).dig('roles', 'webhook', 'explicit_sources_confidence')]
      end

      def check_include_paths(candidates)
        return unless candidates.empty? && !spec.endpoints.empty?

        warn(:include_paths_empty, 'include_paths matched no endpoints', hint: 'check the glob, e.g. /v1/payouts*')
      end

      def conflict(endpoint, role, winner, score)
        warn(:role_conflict, "#{label(endpoint)} also looks like #{role} (#{score}); " \
                             "#{label(winner[0])} wins (#{winner[2]})",
             pointer: endpoint.pointer, hint: "endpoints.#{name(endpoint)}: #{role}")
      end

      def low_confidence(endpoint, role, score)
        return if score >= threshold(:accept)

        message = "#{role}: #{label(endpoint)} scored #{score}"
        warn(:low_confidence, message, pointer: endpoint.pointer, hint: "endpoints.#{name(endpoint)}: #{role}")
      end

      # В URL из operation подставляется только id выплаты (для status/cancel — последний {param});
      # остальные {param} — ids подключения, сервис берёт их из credentials.<param>.
      def check_path_params(assigned)
        assigned.slice(:create, :status, :cancel).each do |role, (endpoint, _score)|
          params = endpoint.path.scan(/\{(\w+)\}/).flatten
          from_credentials = role == :create ? params : params[0..-2]
          next if from_credentials.empty?

          warn(:path_params_from_credentials,
               "#{label(endpoint)}: path params #{from_credentials.join(', ')} are connection-level ids, taken from " \
               "#{from_credentials.map { |p| "credentials.#{p}" }.join(', ')}",
               pointer: endpoint.pointer,
               hint: 'fill them in credentials (INTEGRATION.md) or choose another endpoint via ' \
                     "endpoints.<operationId>: #{role}")
        end
      end

      def check_create(value)
        return if value[:create]

        warn(:no_create_endpoint, 'no create endpoint found',
             hint: 'endpoints.<operationId>: create  (overrides.yml) or --include-paths')
      end

      def source_text(value)
        ROLES.filter_map { |role| "#{role}: #{label(value[role])} (#{value[:confidences][role]})" if value[role] }
             .join('; ')
      end

      def name(endpoint) = endpoint.operation_id || endpoint.path

      def label(endpoint)
        "#{endpoint.method.upcase} #{endpoint.path}#{" (#{endpoint.operation_id})" if endpoint.operation_id}"
      end

      # Факты об одном эндпоинте, по которым считаются сигналы.
      class Facts
        SIMPLE = {
          'method_post' => ->(f) { f.method == 'post' },
          'method_get' => ->(f) { f.method == 'get' },
          'method_delete' => ->(f) { f.method == 'delete' },
          'method_post_or_delete' => ->(f) { %w[post delete].include?(f.method) },
          'has_request_body' => ->(f) { !f.endpoint.request_body.nil? },
          'has_path_param' => lambda(&:path_param?),
          'no_path_param' => ->(f) { !f.path_param? },
          'multi_path_param' => ->(f) { f.endpoint.path.count('{') > 1 },
          'array_response' => ->(f) { f.success_schema&.type == 'array' },
          'security_explicitly_empty' => ->(f) { f.endpoint.security == [] },
          'id_query_param' => ->(f) { f.param_word?('query', 'id') },
          'id_body_field' => ->(f) { !f.id_body_field.nil? },
          'method_post_with_id_body' => ->(f) { f.method == 'post' && !f.id_body_field.nil? },
          'signature_header_param' => ->(f) { f.param_word?('header', 'signature') }
        }.freeze

        attr_reader :endpoint

        def initialize(endpoint, dict, weak_ok: true)
          @endpoint = endpoint
          @dict = dict
          @weak_ok = weak_ok
        end

        def strong_payout_path? = tokens(bare_path).intersect?(@dict['payout_words'])
        def payout_path? = word?('payout', bare_path)

        def requires?(req)
          return true unless req

          Array(req['all']).all? { |f| fact?(f) } && (req['any'].nil? || req['any'].any? { |f| fact?(f) })
        end

        def score(signals, role = nil)
          raw = signals.sum { |name, weight| fact?(name) ? weight : 0.0 }
          penalty = (tokens(bare_path) & @dict['negative_words']).size
          penalty += 1 if role == :create && off_resource? # спека называет ресурс выплат, а create живёт не на нём
          (raw - (penalty * @dict['negative_penalty'])).clamp(0.0, 1.0).round(2)
        end

        # В спеке есть пути с сильным словом выплаты, а этот путь без него (/v2/payments, /v2/bank-accounts у Square).
        def off_resource? = !@weak_ok && !strong_payout_path?

        def method = endpoint.method
        def path_param? = endpoint.path.include?('{')
        def success_schema = endpoint.responses.find { |r| r.status.start_with?('2') }&.schema

        # Поле тела с id-словом в имени и без других обязательных полей кроме credentials-подобных.
        def id_body_field
          return nil unless endpoint.method == 'post' && !path_param?

          props = endpoint.request_body&.schema&.properties.to_h
          props.keys.find { |name| name.end_with?('_id') || name == 'id' }
        end

        def param_word?(location, list)
          endpoint.parameters.any? { |p| p.location == location && word?(list, p.name) }
        end

        private

        def fact?(name)
          return SIMPLE[name].call(self) if SIMPLE[name]

          case name
          when /\A(\w+)_word_in_path\z/ then word?(::Regexp.last_match(1), bare_path)
          when /\A(\w+)_word_in_operation\z/ then word?(::Regexp.last_match(1), endpoint.operation_id)
          when /\A(\w+)_word\z/ then word?(::Regexp.last_match(1), endpoint.operation_id, endpoint.summary,
                                           *endpoint.tags)
          else false
          end
        end

        # Список слов: `payout_words` на верхнем уровне словаря, остальные — в `words`.
        def word?(list, *texts)
          words = @dict.fetch("#{list}_words") { @dict['words'].fetch(list) }
          words += weak_words if list == 'payout' && @weak_ok
          texts.compact.any? { |t| tokens(t).intersect?(words) }
        end

        def weak_words = @dict.fetch('weak_payout_words', [])
        def bare_path = endpoint.path.gsub(/\{[^}]*\}/, '')
        def tokens(text) = Rules.normalize(text).split(%r{[_/]}).reject(&:empty?)
      end
    end
  end
end
