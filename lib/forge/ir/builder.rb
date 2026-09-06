# frozen_string_literal: true

module Forge
  module IR
    # Hash (после Loader) → IR::Spec. Знает только об OpenAPI-структуре.
    class Builder
      HTTP_METHODS = %w[get post put patch delete head options trace].freeze
      JSON_TYPES = [->(k) { k == 'application/json' }, ->(k) { k.match?(%r{\Aapplication/.*\+json\z}) }].freeze

      def self.build(hash, source_path: nil) = new(hash, source_path).build

      def initialize(hash, source_path)
        @hash = hash
        @source_path = source_path
      end

      def build
        info = @hash['info'] || {}
        Spec.new(title: info['title'], version: info['version'], openapi_version: @hash['openapi'],
                 description: info['description'], servers: servers, security_schemes: security_schemes,
                 default_security: @hash['security'], endpoints: endpoints, webhooks: callbacks + webhooks,
                 schemas: @hash.dig('components', 'schemas').to_h.transform_values { |s| Schema.from(s) },
                 source_path: @source_path)
      end

      private

      def servers
        Array(@hash['servers']).map do |s|
          Server.new(url: s['url'].to_s.chomp('/'), description: s['description'],
                     alternatives: s.fetch('x-forge-url-alternatives', []))
        end
      end

      def security_schemes
        @hash.dig('components', 'securitySchemes').to_h.map do |name, scheme|
          s = scheme.to_h
          SecurityScheme.new(name: name, type: s['type'].to_s, location: s['in'], param_name: s['name'],
                             scheme: s['scheme'], bearer_format: s['bearerFormat'], description: s['description'],
                             token_url: s['flows'].to_h.dig('clientCredentials', 'tokenUrl'))
        end
      end

      def endpoints
        each_operation(@hash['paths'], '#/paths', :paths).map do |ep|
          ep.with(security: ep.security || @hash['security'])
        end
      end

      def callbacks
        endpoints.flat_map do |ep|
          ep.callbacks.to_h.flat_map do |name, paths|
            each_operation(paths, "#{ep.pointer}/callbacks/#{escape(name)}", :callbacks)
          end
        end
      end

      # OpenAPI 3.1 `webhooks` и распространённое расширение 3.0 `x-webhooks` (Redoc-стиль).
      def webhooks
        %w[webhooks x-webhooks].flat_map do |key|
          @hash[key].to_h.flat_map do |name, item|
            operations(item, "#/#{escape(key)}/#{escape(name)}", name, :webhooks)
          end
        end
      end

      # `x-*` в paths — расширения (OAS), а не пути.
      def each_operation(paths, pointer, source)
        paths.to_h.reject { |path, _| path.start_with?('x-') }
             .flat_map { |path, item| operations(item, "#{pointer}/#{escape(path)}", path, source) }
      end

      # `null` у path item / операции (черновик «post:») = пустой объект.
      def operations(item, pointer, path, source)
        item = item.to_h
        item.slice(*HTTP_METHODS).map do |method, op|
          endpoint(op.to_h, parameters(item, op.to_h), method: method, path: path, source: source,
                                                       pointer: "#{pointer}/#{method}")
        end
      end

      def parameters(item, operation)
        (Array(item['parameters']) + Array(operation['parameters'])).uniq { |p| [p['name'], p['in']] }
                                                                    .map { |p| parameter(p) }
      end

      def endpoint(operation, params, **where)
        Endpoint.new(operation_id: operation['operationId'], summary: operation['summary'],
                     description: operation['description'], tags: operation['tags'], security: operation['security'],
                     parameters: params, request_body: request_body(operation['requestBody']),
                     responses: responses(operation['responses']), callbacks: operation['callbacks'], **where)
      end

      def parameter(param)
        Parameter.new(name: param['name'].to_s, location: param['in'].to_s, required: param['required'] == true,
                      schema: Schema.from(param['schema']), description: param['description'],
                      example: param['example'])
      end

      def request_body(body)
        return nil unless body.is_a?(Hash)

        media_type, media = pick_media(body['content'])
        RequestBody.new(required: body['required'] == true, media_type: media_type,
                        media_types: body['content'].to_h.keys, schema: Schema.from(media&.[]('schema')),
                        examples: examples(media))
      end

      def responses(hash)
        hash.to_h.map do |status, response|
          res = response.to_h
          media_type, media = pick_media(res['content'])
          Response.new(status: status.to_s, description: res['description'], media_type: media_type,
                       schema: Schema.from(media&.[]('schema')), examples: examples(media),
                       headers: res['headers'].to_h.transform_values { |h| Schema.from(h.to_h['schema']) })
        end
      end

      # application/json → application/*+json → первый.
      def pick_media(content)
        return [nil, nil] unless content.is_a?(Hash) && !content.empty?

        key = JSON_TYPES.lazy.filter_map { |t| content.keys.find(&t) }.first || content.keys.first
        [key, content[key]]
      end

      # `examples: {name: {value: ...}}` + `example: ...` → {name => value}.
      # `examples` + `example` + расширение `x-examples` ({name: {...}} или {name: {value: ...}}).
      def examples(media)
        return {} unless media.is_a?(Hash)

        raw = media['examples'].to_h.merge(media['x-examples'].to_h)
        named = raw.transform_values { |e| e.is_a?(Hash) && e.key?('value') ? e['value'] : e }
        media.key?('example') ? named.merge('example' => media['example']) : named
      end

      def escape(key) = key.to_s.gsub('~', '~0').gsub('/', '~1')
    end
  end
end
