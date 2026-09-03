# frozen_string_literal: true

module Forge
  Finding = Data.define(:key, :value, :confidence, :source, :warnings)
  Warning = Data.define(:level, :code, :message, :pointer, :hint) # level: :warn | :unsupported | :info

  module Analyzers
    # Общее для анализаторов: доступ к spec/rules, пороги, накопление предупреждений, нормализация.
    class Base
      attr_reader :spec, :rules, :warnings, :roles

      # roles: значение Finding из EndpointRoles (для анализаторов, которым нужен create/status/...).
      def initialize(spec, rules, include_paths: [], roles: nil)
        @spec = spec
        @rules = rules
        @include_paths = include_paths
        @roles = roles || {}
        @warnings = []
      end

      def call
        raise NotImplementedError
      end

      private

      def threshold(name) = rules.thresholds.fetch(name.to_s)

      def warn(code, message, pointer: nil, hint: nil)
        @warnings << Warning.new(level: :warn, code: code, message: message, pointer: pointer, hint: hint)
      end

      def info(code, message, pointer: nil, hint: nil)
        @warnings << Warning.new(level: :info, code: code, message: message, pointer: pointer, hint: hint)
      end

      def unsupported(code, message, pointer: nil, hint: nil)
        @warnings << Warning.new(level: :unsupported, code: code, message: message, pointer: pointer, hint: hint)
      end

      def finding(key, value, confidence:, source:)
        Finding.new(key: key, value: value, confidence: confidence.clamp(0.0, 1.0).round(2), source: source,
                    warnings: warnings.dup)
      end

      # Токены нормализованной строки: 'createPayout' → ['create', 'payout'].
      def tokens(text) = Rules.normalize(text).split('_').reject(&:empty?)

      def word_in?(words, *texts) = texts.flatten.compact.any? { |t| tokens(t).intersect?(words) }

      def role(name) = roles[name]

      # Схема успешного ответа (2xx) эндпоинта.
      def success_response(endpoint)
        endpoint&.responses&.find { |r| r.status.start_with?('2') }
      end

      # Свойство по пути внутри Schema: dig_schema(schema, %w[data state]).
      def dig_schema(schema, path)
        path.reduce(schema) { |node, key| node&.properties&.[](key) }
      end

      # Эндпоинты с учётом --include-paths (glob по path).
      def endpoints
        return spec.endpoints if @include_paths.empty?

        spec.endpoints.select { |ep| @include_paths.any? { |glob| File.fnmatch(glob, ep.path) } }
      end
    end
  end
end
