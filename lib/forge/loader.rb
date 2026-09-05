# frozen_string_literal: true

require 'date'
require 'json'
require 'yaml'
require_relative 'ref_resolver'

module Forge
  # Файл → Hash: парсинг YAML/JSON, базовые проверки OpenAPI 3, server variables, резолв `$ref`.
  class Loader
    def self.load(path) = new(path).load

    def initialize(path)
      @path = path
    end

    def load
      spec = parse(read)
      validate(spec)
      substitute_servers(spec)
      RefResolver.resolve(spec, file: @path)
    end

    private

    def read
      File.read(@path)
    rescue Errno::ENOENT
      raise SpecError.new('file not found', file: @path, hint: 'check the --spec path')
    end

    def parse(text)
      doc = case File.extname(@path).downcase
            when '.json' then JSON.parse(text)
            when '.yaml', '.yml' then parse_yaml(text)
            else parse_any(text)
            end
      raise error('empty document', 'the file has no content') if doc.nil?
      raise error('root must be an object', 'top level must be an OpenAPI document (mapping)') unless doc.is_a?(Hash)

      doc
    rescue JSON::ParserError, Psych::SyntaxError => e
      raise error("cannot parse: #{e.message.lines.first&.strip}", 'the file must be valid YAML or JSON')
    end

    def parse_yaml(text) = YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true)

    def parse_any(text)
      parse_yaml(text)
    rescue Psych::SyntaxError
      JSON.parse(text)
    end

    def validate(spec)
      if spec.key?('swagger')
        raise error('Swagger 2.0 is not supported; convert to OpenAPI 3', 'use swagger2openapi or similar', '#/swagger')
      end

      validate_version(spec['openapi'])
      paths = spec['paths']
      return if paths.is_a?(Hash) && !paths.empty?

      raise error('no paths', no_paths_hint(spec), '#/paths')
    end

    def no_paths_hint(spec)
      return 'the document must declare at least one path' unless spec.key?('webhooks') || spec.key?('x-webhooks')

      'this document describes only webhooks; payout endpoints (paths) are needed'
    end

    def validate_version(version)
      raise error("missing 'openapi'", 'add `openapi: 3.0.3` to the root', '#/openapi') unless version
      return if version.to_s.start_with?('3.')

      raise error("unsupported openapi version #{version}", 'only 3.x is supported', '#/openapi')
    end

    # `https://{env}.x/api` + variables.env.default → подставляем; enum сохраняем как альтернативы.
    def substitute_servers(spec)
      Array(spec['servers']).each do |server|
        vars = server['variables']
        next unless vars.is_a?(Hash) && server['url']

        alternatives = expand(server['url'], vars)
        server['url'] = alternatives.shift
        server['x-forge-url-alternatives'] = alternatives unless alternatives.empty?
      end
    end

    def expand(url, vars)
      vars.reduce([url]) do |urls, (name, var)|
        values = [var['default'], *Array(var['enum'])].compact.uniq
        urls.flat_map { |u| values.map { |v| u.gsub("{#{name}}", v.to_s) } }
      end.uniq
    end

    def error(message, hint, pointer = nil)
      SpecError.new(message, pointer: pointer, file: @path, hint: hint)
    end
  end
end
