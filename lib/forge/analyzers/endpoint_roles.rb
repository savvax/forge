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
        best = candidates.filter_map do |endpoint|
          role, score = scores(endpoint).max_by { |_role, points| points }
          [endpoint, role, score] if score && score >= threshold(:warn)
        end
        best.group_by { |(_endpoint, role, _score)| role }.to_h { |role, group| [role, pick_winner(role, group)] }
      end

      def pick_winner(role, group)
        # Равные очки: короче путь (каноничнее ресурс: /transfer/create < /transfer/x/y/create), затем порядок в спеке.
        winner, *losers = group.sort_by.with_index { |(ep, _role, score), index| [-score, ep.path.count('/'), index] }
        losers.each { |(endpoint, _role, score)| conflict(endpoint, role, winner, score) }
        low_confidence(winner[0], role, winner[2])
        [winner[0], winner[2]]
      end

      def scores(endpoint)
        dict = rules.fetch(:endpoint_roles)
        facts = Facts.new(endpoint, dict)
        dict['roles'].filter_map do |role, cfg|
          [role.to_sym, facts.score(cfg['signals'])] if facts.requires?(cfg['requires'])
        end
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
          'security_explicitly_empty' => ->(f) { f.endpoint.security == [] },
          'id_query_param' => ->(f) { f.param_word?('query', 'id') },
          'signature_header_param' => ->(f) { f.param_word?('header', 'signature') }
        }.freeze

        attr_reader :endpoint

        def initialize(endpoint, dict)
          @endpoint = endpoint
          @dict = dict
        end

        def requires?(req)
          return true unless req

          Array(req['all']).all? { |f| fact?(f) } && (req['any'].nil? || req['any'].any? { |f| fact?(f) })
        end

        def score(signals)
          raw = signals.sum { |name, weight| fact?(name) ? weight : 0.0 }
          penalty = (tokens(bare_path) & @dict['negative_words']).size * @dict['negative_penalty']
          (raw - penalty).clamp(0.0, 1.0).round(2)
        end

        def method = endpoint.method
        def path_param? = endpoint.path.include?('{')

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
          texts.compact.any? { |t| tokens(t).intersect?(words) }
        end

        def bare_path = endpoint.path.gsub(/\{[^}]*\}/, '')
        def tokens(text) = Rules.normalize(text).split(%r{[_/]}).reject(&:empty?)
      end
    end
  end
end
