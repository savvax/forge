# frozen_string_literal: true

require 'did_you_mean'
require 'yaml'
require_relative 'overrides_apply'

module Forge
  module Plan
    # overrides.yml: схема ключей, did-you-mean, загрузка. Применение — OverridesApply (docs/RULES.md § 9).
    module Overrides
      SCHEMA = {
        'provider' => %w[name class_name], 'paths' => %w[include],
        'base_url' => %w[default production env_var], 'endpoints' => :any,
        'auth' => %w[type header prefix credential_key], 'statuses' => :any, 'events' => :any,
        'amount' => %w[unit multiplier minimum_major], 'fields' => :fields,
        'webhook' => %w[signature_header signature_algorithm signature_encoding signature_payload event_field
                        id_field status_field],
        'errors' => :any
      }.freeze
      FIELD_KEYS = %w[source required required_if variant].freeze
      ROLES = %w[create status cancel balance webhook other].freeze

      module_function

      def load(path)
        unless File.file?(path)
          raise SpecError.new('overrides file not found', file: path,
                                                          hint: 'check the --overrides path')
        end

        hash = parse(path)
        unless hash.is_a?(Hash)
          raise SpecError.new('overrides must be a mapping', file: path,
                                                             hint: 'see docs/RULES.md § 9')
        end

        validate!(hash, path)
        hash
      end

      def parse(path)
        YAML.safe_load_file(path) || {}
      rescue Psych::Exception => e
        raise SpecError.new("cannot parse: #{e.message.lines.first&.strip}", file: path,
                                                                             hint: 'overrides.yml must be valid YAML')
      end

      def validate!(hash, file)
        hash.each do |key, value|
          allowed = SCHEMA[key] || unknown!(key, SCHEMA.keys, file, '')
          next if value.nil?

          must!(value.is_a?(Hash), "overrides key '#{key}' must be a mapping", file)
          next if allowed == :any

          allowed == :fields ? validate_fields!(value, file) : validate_keys!(value, allowed, file, "#{key}.")
        end
      end

      def validate_fields!(fields, file)
        fields.each do |path, rules|
          next if rules.nil?

          must!(rules.is_a?(Hash), "'fields.#{path}' must be a mapping", file)
          validate_keys!(rules, FIELD_KEYS, file, "fields.#{path}.")
          cond = rules['required_if']
          must!(cond.nil? || cond.is_a?(Hash), "'fields.#{path}.required_if' must be a mapping {field, equals}", file)
        end
      end

      def validate_keys!(hash, allowed, file, prefix)
        hash.each_key { |k| unknown!(k, allowed, file, prefix) unless allowed.include?(k.to_s) }
        return unless prefix == 'amount.'

        %w[multiplier minimum_major].each do |k|
          must!(hash[k].nil? || hash[k].is_a?(Numeric), "'amount.#{k}' must be a number", file)
        end
      end

      def must!(condition, message, file)
        raise SpecError.new(message, file: file, hint: 'see docs/RULES.md § 9') unless condition
      end

      def unknown!(key, allowed, file, prefix)
        suggestion = DidYouMean::SpellChecker.new(dictionary: allowed).correct(key.to_s).first
        hint = suggestion ? "did you mean #{prefix}#{suggestion}?" : "allowed: #{allowed.join(', ')}"
        raise SpecError.new("unknown overrides key '#{prefix}#{key}'", file: file, hint: hint)
      end
    end
  end
end
