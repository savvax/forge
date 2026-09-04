# frozen_string_literal: true

require 'yaml'

module Forge
  # Словари rules/*.yml: загружаются один раз, замораживаются. Нормализация слов (docs/RULES.md § 0).
  class Rules
    DEFAULT_DIR = File.expand_path('../../rules', __dir__)

    def self.load(dir = DEFAULT_DIR)
      unless File.directory?(dir)
        raise GenerationError.new("rules directory not found: #{dir}", hint: 'run from the project root')
      end

      new(dir)
    end

    # camelCase, `-`, `.`, пробел → snake_case.
    def self.normalize(word)
      word.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[-.\s]+/, '_').downcase
    end

    def initialize(dir)
      @dir = dir
      @cache = {}
    end

    def thresholds = fetch(:thresholds)

    def fetch(name)
      @cache[name] ||= begin
        path = File.join(@dir, "#{name}.yml")
        unless File.exist?(path)
          raise GenerationError.new("rules file not found: #{path}",
                                    hint: 'restore it from the repository')
        end

        deep_freeze(YAML.safe_load_file(path))
      end
    end

    private

    def deep_freeze(node)
      case node
      when Hash then node.each_value { |v| deep_freeze(v) }
      when Array then node.each { |v| deep_freeze(v) }
      end
      node.freeze
    end
  end
end
