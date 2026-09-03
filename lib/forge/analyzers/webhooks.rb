# frozen_string_literal: true

require_relative 'base'

module Forge
  module Analyzers
    # Webhook: эндпоинт, подпись (заголовок/алгоритм/кодировка/payload), поле события и его маппинг.
    class Webhooks < Base
      def call
        endpoint = role(:webhook)
        return none unless endpoint

        signature, confidence = signature(endpoint)
        schema = endpoint.request_body&.schema
        event_field, event_map = events(schema)
        status_field = field_path(schema, status_dict['status_fields'])
        value = { endpoint: endpoint, source: endpoint.source, event_field: event_field, event_map: event_map,
                  id_field: field_path(schema, status_dict['id_fields'], near: status_field),
                  status_field: status_field, signature: signature }
        finding(:webhooks, value, confidence: confidence,
                                  source: "#{endpoint.method.upcase} #{endpoint.path} (#{endpoint.source})")
      end

      private

      def dict = rules.fetch(:webhook_signature)
      def status_dict = rules.fetch(:status_map)

      def signature(endpoint)
        header = signature_header(endpoint)
        return [no_header, 0.0] unless header

        text = [header.description, endpoint.description, endpoint.summary].compact.join("\n")
        found = detect(text)
        found.each { |kind, value| assumed(kind, header.name) unless value }
        timestamp(header.name, text)
        [{ header: header.name, **dict['defaults'].transform_keys(&:to_sym).merge(found.compact),
           secret_key: dict['secret_credential_key'] }, score(found)]
      end

      def detect(text)
        { algorithm: algorithm(text), encoding: by_markers(dict['encoding'], text),
          payload: by_markers(dict['payload'], text) }
      end

      def signature_header(endpoint)
        endpoint.parameters.find do |p|
          p.location == 'header' && dict['header_markers'].any? { |m| p.name.downcase.include?(m) }
        end
      end

      def score(found)
        weights = dict['signals']
        total = weights['header_found']
        total += weights['algorithm_in_description'] if found[:algorithm]
        total += weights['encoding_in_description'] if found[:encoding]
        total += weights['payload_in_description'] if found[:payload]
        total.round(2)
      end

      def algorithm(text)
        match = text.match(Regexp.new(dict['algorithm_regex'], Regexp::IGNORECASE))
        match && "sha#{match[2]}"
      end

      def by_markers(groups, text)
        lower = text.downcase
        groups.find { |_name, markers| markers.any? { |m| lower.include?(m.downcase) } }&.first
      end

      def assumed(kind, header)
        values = { algorithm: 'sha256|sha512|sha1', encoding: 'hex|base64', payload: 'raw_body|fields' }.fetch(kind)
        warn(:"signature_#{kind}_assumed", "#{header}: #{kind} not stated; #{dict['defaults'][kind.to_s]} assumed",
             hint: "webhook.signature_#{kind}: #{values}  (overrides.yml)")
      end

      def timestamp(header, text)
        return unless dict['timestamp_markers'].any? { |m| text.downcase.include?(m) }

        unsupported(:signature_with_timestamp, "#{header}: signature includes a timestamp/nonce; verify is a TODO",
                    hint: 'implement verify_signature! by hand following the provider docs')
      end

      def no_header
        warn(:signature_not_found, 'webhook has no signature header parameter; callbacks will not be verified',
             hint: 'webhook.signature_header: <Header-Name>  (overrides.yml)')
        { header: nil, algorithm: nil, encoding: nil, payload: nil, secret_key: dict['secret_credential_key'] }
      end

      # Поле события с enum → {event => internal_status}; без enum → {}.
      def events(schema)
        name, prop = schema&.properties.to_h.find { |n, _| dict['event_fields'].include?(n) }
        return [name, {}] unless prop&.enum

        [name, event_map(prop.enum)]
      end

      def event_map(enum)
        map = enum.to_h { |event| [event.to_s, status_for(event.to_s)] }
        map.each { |event, status| unmapped_event(event) if status.nil? }
        map.compact
      end

      def status_for(event)
        key = event_status(event)
        %w[in_progress approved rejected].find { |k| status_dict[k].include?(key) }
      end

      # 'payout.completed' → 'completed', 'transfer.on_hold' → 'on_hold' (срезаем префиксы-слова выплат).
      def event_status(event)
        tokens = Rules.normalize(event).split('_')
        prefixes = rules.fetch(:endpoint_roles)['payout_words'] + %w[event]
        tokens.shift while tokens.size > 1 && prefixes.include?(tokens.first)
        tokens.join('_')
      end

      def unmapped_event(event)
        warn(:unmapped_event, "webhook event '#{event}' → status '#{event_status(event)}' unknown",
             hint: "events.#{event}: in_progress|approved|rejected  (overrides.yml)")
      end

      # Первое поле с именем из names; при near — сначала в том же контейнере (id рядом со status).
      def field_path(schema, names, near: nil)
        paths = candidates(schema).map(&:first).select { |path| names.include?(path.last) }
        (near && paths.find { |path| path[0..-2] == near[0..-2] }) || paths.first
      end

      def candidates(schema, prefix = [], depth = 0)
        return [] unless schema&.properties

        schema.properties.flat_map do |name, prop|
          nested = if depth < 2 && status_dict['wrappers'].include?(name)
                     candidates(prop, prefix + [name],
                                depth + 1)
                   else
                     []
                   end
          [[prefix + [name], prop]] + nested
        end
      end

      def none
        warn(:no_webhook, 'no webhook endpoint, callbacks or webhooks found; process_callback will be a stub',
             hint: 'endpoints.<operationId>: webhook  (overrides.yml)')
        value = { endpoint: nil, source: nil, event_field: nil, event_map: {}, id_field: nil, status_field: nil,
                  signature: { header: nil } }
        finding(:webhooks, value, confidence: 0.0, source: 'no webhook found')
      end
    end
  end
end
