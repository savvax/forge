# frozen_string_literal: true

require 'thor'
require_relative '../forge'

module Forge
  # Thor-команды. Ошибки Forge::Error печатаются без стектрейса (кроме --debug) с кодом выхода класса.
  class CLI < Thor
    def self.exit_on_failure? = true

    class_option :debug, type: :boolean, default: false, desc: 'Печатать стектрейс при ошибке'

    desc 'analyze', 'Разобрать OpenAPI-спеку и напечатать отчёт'
    option :spec, required: true, desc: 'OpenAPI 3.x файл (YAML/JSON)'
    option :overrides, desc: 'overrides.yml (применяется в generate; здесь пока только проверяется наличие)'
    option :include_paths, type: :array, default: [], desc: 'glob по path, ограничивает анализ'
    option :format, default: 'text', enum: %w[text json]
    def analyze
      guarded do
        spec, findings = analyze_spec(options)
        puts options[:format] == 'json' ? Report.json(spec, findings) : Report.text(spec, findings)
      end
    end

    desc 'generate', 'Сгенерировать интеграцию провайдера'
    option :spec, required: true
    option :provider
    option :out, default: 'output'
    def generate = not_implemented

    desc 'mock', 'Поднять мок-сервер провайдера из спеки'
    option :spec, required: true
    def mock = not_implemented

    desc 'version', 'Версия forge'
    def version = puts("forge #{Forge::VERSION}")

    private

    def analyze_spec(opts)
      hash = Loader.load(opts[:spec])
      spec = IR::Builder.build(hash, source_path: opts[:spec])
      [spec, Analyzers::Runner.run(spec, rules: Rules.load, include_paths: opts[:include_paths])]
    end

    def guarded
      yield
    rescue Forge::Error => e
      raise if options[:debug]

      warn "error: #{e.message}"
      exit e.class.exit_code
    end

    def not_implemented
      warn 'error: not implemented'
      exit GenerationError.exit_code
    end
  end
end
