# frozen_string_literal: true

require_relative 'service_payload'
require_relative 'service_paths'

module Forge
  module Renderers
    # Строки и фрагменты для service.rb.erb: константы, валидации, подпись; пути/dig — ServicePaths.
    class ServiceView
      MINOR_NAMES = { 'RUB' => 'kopecks', 'USD' => 'cents', 'EUR' => 'cents', 'GBP' => 'pence' }.freeze
      FAIL = 'return failure(:unprocessable_entity, '

      attr_reader :plan, :paths

      def initialize(plan)
        @plan = plan
        @payload = ServicePayload.new(plan)
        @paths = ServicePaths.new(plan)
      end

      def op(role) = plan.operations[role]
      def webhook = plan.webhook
      def signature = webhook&.dig(:signature)
      def signature? = !signature&.dig(:header).nil?
      def minor? = plan.amount[:unit] == :minor
      def currency = plan.amount[:currencies].first
      def requisites? = !plan.requisite_types.empty?
      def idempotency? = !op(:create).headers.empty?

      def requires
        base64 = plan.auth[:type] == 'basic' || signature&.dig(:encoding) == 'base64'
        %w[base64 json openssl].select { |r| r != 'base64' || base64 }
      end

      def aligned(hash)
        width = hash.keys.map { |k| k.to_s.size }.max + 2
        hash.map { |k, v| "#{"'#{k}'".ljust(width)} => '#{v}'" }
      end

      def error_map_lines = plan.error_map.map { |status, e| "#{status} => '#{e[:internal_code]}'" }

      def success_comment
        dup = plan.success_statuses - op(:create).success_statuses.first(1)
        return '' if dup.empty?

        key = op(:create).headers.first&.provider_field
        " # #{dup.first}: duplicate#{" by #{key}" if key} returns the payout"
      end

      def minor_comment = "amount is sent in minor units (#{MINOR_NAMES.fetch(currency, 'minor units')})"

      def min_comment
        minimum = plan.fields[:request].find { |m| m.transform == 'amount' }&.schema&.minimum
        "#{currency}; schema minimum #{minimum}#{' minor units' if minor?}"
      end

      # Валидации check_conditions в порядке: min, max, currency, maxLength, requisite, pattern.
      def validations
        by = plan.validations.group_by { |v| v[:rule] }
        lines = []
        lines << "#{FAIL}'amount_too_low') if operation.amount < MIN_AMOUNT" if by[:min]
        lines << "#{FAIL}'amount_too_high') if operation.amount > MAX_AMOUNT" if by[:max]
        if by[:enum]
          lines << "#{FAIL}'currency_not_supported') unless SUPPORTED_CURRENCIES.include?(operation.currency)"
        end
        by.fetch(:max_length, []).each do |v|
          lines << "#{FAIL}'#{v[:error_code]}') if #{length_expr(v)} > #{v[:value]}"
        end
        lines << "#{FAIL}'requisite_missing') unless requisite_type_for(operation, request_method)" if requisites?
        lines
      end

      def pattern_checks = plan.validations.select { |v| v[:rule] == :pattern }.map { |v| pattern_check(v) }

      def length_expr(validation)
        expr = validation[:expr]
        return "#{expr}.length" if expr.end_with?('.to_s')

        expr.match?(/\A[\w.]+\z/) ? "#{expr}.to_s.length" : "(#{expr}).to_s.length"
      end

      def pattern_check(validation)
        name = validation[:field].split('.').last
        expr = validation[:expr].sub('requisite_type', 'requisite_type_for(operation, request_method)')
        regexp = validation[:value].sub(/\A\^/, '\A').sub(/\$\z/, '\z').gsub('/', '\/')
        check = "#{name}.to_s.match?(/#{regexp}/)"
        type = validation[:requisite_type]
        guard = "requisite_type_for(operation, request_method) == '#{type}'"
        condition = type ? "if #{guard} && !#{check}" : "unless #{check}"
        ["#{name} = #{expr}", "#{FAIL}'#{validation[:error_code]}') #{condition}"]
      end

      def hmac_expr
        algo = signature[:algorithm].to_s.upcase
        secret = "credentials.fetch('#{signature[:secret_key]}')"
        if signature[:encoding] == 'base64'
          return "Base64.strict_encode64(OpenSSL::HMAC.digest('#{algo}', #{secret}, raw_body))"
        end

        "OpenSSL::HMAC.hexdigest('#{algo}', #{secret}, raw_body)"
      end

      def signature_comment
        assumed = plan.warnings.filter_map { |w| w.code.to_s[/\Asignature_(\w+)_assumed\z/, 1] }
        note = assumed.empty? ? '' : " (#{assumed.join(', ')} assumed: not stated in the spec)"
        over = { 'raw_body' => 'raw request body', 'fields' => 'concatenated fields' }.fetch(signature[:payload].to_s,
                                                                                             'body')
        "HMAC-#{signature[:algorithm].to_s.upcase} over the #{over}, #{signature[:encoding]}-encoded#{note}."
      end

      def timestamp_unsupported? = plan.warnings.any? { |w| w.code == :signature_with_timestamp }

      def payload_lines = @payload.payload_lines
      def recipient_lines = @payload.recipient_lines
      def container? = @payload.container?
      def variants? = @payload.variants?
    end
  end
end
