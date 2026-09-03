# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Ответы ≥ 400 у create/status/cancel → код провайдера, внутренний код, действие (rules/error_actions.yml).
    class Errors < Base
      ROLES = %i[create status cancel].freeze

      def call
        rows = ROLES.flat_map { |name| role(name) ? error_rows(name, role(name)) : [] }
        value = { rows: rows, http: http_map(rows), codes: code_enum(rows), retry_after_header: retry_after(rows) }
        finding(:errors, value, confidence: rows.empty? ? 0.5 : 0.9,
                                source: "#{rows.size} error responses across #{ROLES.join('/')}")
      end

      private

      def dict = rules.fetch(:error_actions)

      def error_rows(name, endpoint)
        success = success_response(endpoint)&.schema&.ref_name
        endpoint.responses.select { |r| r.status.to_i >= 400 }.map { |res| row(name, endpoint, res, success) }
      end

      def row(name, endpoint, res, success_ref)
        status = res.status.to_i
        base = { status: status, role: name, pointer: "#{endpoint.pointer}/responses/#{status}",
                 headers: res.headers.keys }
        return base.merge(duplicate_as_success(res, status)) if success_ref && res.schema&.ref_name == success_ref

        code = provider_code(res, status)
        action = (code && dict['codes'][code]) || dict['http'][status] || unknown_status(status, base[:pointer])
        base.merge(provider_code: code, internal_code: action['internal_code'], action: action['action'])
      end

      def duplicate_as_success(res, status)
        info(:duplicate_as_success, "HTTP #{status} returns the success schema (#{res.schema.ref_name}); " \
                                    'treated as success', hint: 'the service reads the payout from the body')
        { provider_code: nil, internal_code: 'duplicate', action: 'treat_as_success' }
      end

      # Пример по error_code_paths; иначе первый enum схемы, но только если он согласуется с HTTP-статусом.
      def provider_code(res, status)
        from_example = code_from_example(res.examples.values.first)
        return from_example if from_example

        code = enum_property(res.schema)&.enum&.first.to_s
        code if !code.empty? && dict['codes'].dig(code, 'internal_code') == dict['http'].dig(status, 'internal_code')
      end

      def code_from_example(example)
        return nil unless example

        dict['error_code_paths'].lazy.filter_map { |p| dig_path(example, p.split('.')) }.first&.to_s
      end

      def dig_path(node, keys)
        keys.reduce(node) do |cur, key|
          case cur
          when Hash then cur[key]
          when Array then cur[key.to_i]
          end
        end
      end

      def unknown_status(status, pointer)
        warn(:unknown_http_status, "HTTP #{status} is not in the error dictionary; reject assumed",
             pointer: pointer, hint: "errors.#{status}: { internal_code: <code>, action: reject|retry|alert_block }")
        { 'internal_code' => 'unknown_error', 'action' => 'reject' }
      end

      # {status => internal_code} для ERROR_MAP сервиса: create + status, без treat_as_success (cancel — своя ветка).
      def http_map(rows)
        rows.reject { |r| r[:action] == 'treat_as_success' || r[:role] == :cancel }.sort_by { |r| r[:status] }
            .each_with_object({}) { |r, map| map[r[:status]] ||= r[:internal_code] }
      end

      # Все enum кодов из схем ошибок (без ответов со схемой успеха) — для INTEGRATION.md.
      def code_enum(rows)
        error_rows = rows.reject { |r| r[:action] == 'treat_as_success' }
        error_rows.flat_map { |r| enum_property(response_for(r)&.schema)&.enum.to_a }.map(&:to_s).uniq
      end

      def response_for(row)
        role(row[:role]).responses.find { |res| res.status.to_i == row[:status] }
      end

      # Первое свойство с enum (обычно `code`) в схеме ошибки, глубина ≤ 3.
      def enum_property(schema, depth = 0)
        return nil if schema.nil? || depth > 3
        return schema if schema.enum

        children = (schema.properties || {}).values + [schema.items]
        children.lazy.filter_map { |child| enum_property(child, depth + 1) }.first
      end

      def retry_after(rows)
        rows.flat_map { |r| r[:headers] }.find { |h| dict['retry_after_headers'].include?(h) }
      end
    end
  end
end
