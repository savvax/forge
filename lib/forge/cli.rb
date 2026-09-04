# frozen_string_literal: true

require 'thor'
require_relative '../forge'
require_relative 'generate_command'

module Forge
  # Thor-команды. Ошибки Forge::Error печатаются без стектрейса (кроме --debug) с кодом выхода класса.
  class CLI < Thor
    def self.exit_on_failure? = true

    class_option :debug, type: :boolean, default: false, desc: 'Печатать стектрейс при ошибке'

    desc 'analyze', 'Разобрать OpenAPI-спеку и напечатать отчёт'
    option :spec, required: true, desc: 'OpenAPI 3.x файл (YAML/JSON)'
    option :overrides, desc: 'overrides.yml — переопределения решений анализа (docs/RULES.md § 9)'
    option :include_paths, type: :array, default: [], repeatable: true, desc: 'glob по path (повторяемый)'
    option :format, default: 'text', enum: %w[text json]
    def analyze
      guarded do
        spec, findings = GenerateCommand.analyze(options)
        puts options[:format] == 'json' ? Report.json(spec, findings) : Report.text(spec, findings)
      end
    end

    desc 'generate', 'Сгенерировать интеграцию провайдера (docs/OUTPUT_FORMAT.md)'
    option :spec, required: true
    option :provider, desc: 'имя провайдера (иначе из info.title)'
    option :out, default: 'output', desc: 'каталог вывода'
    option :overrides
    option :include_paths, type: :array, default: [], repeatable: true
    option :templates_dir, desc: 'каталог с переопределёнными шаблонами *.erb'
    option :lang, default: 'ruby', enum: %w[ruby]
    option :format, default: 'text', enum: %w[text json]
    option :strict, type: :boolean, default: false, desc: 'exit 4, если есть WARN/UNSUPPORTED'
    option :verify, type: :boolean, default: true, desc: '--no-verify пропускает rspec сгенерированного spec'
    option :force, type: :boolean, default: false, desc: 'перезаписать непустой каталог'
    def generate
      guarded { exit GenerateCommand.new(options).run }
    end

    desc 'mock', 'Поднять мок-сервер провайдера из спеки (Sinatra, docs/OUTPUT_FORMAT.md § 5)'
    option :spec, required: true
    option :port, type: :numeric, default: 4567
    option :webhook_url, desc: 'куда мок шлёт webhook при POST /_simulate/:id/:event'
    option :overrides
    option :out, default: 'tmp/mock', desc: 'куда рендерить файлы мока'
    def mock
      guarded { GenerateCommand.new(options.merge(include_paths: [], force: true, verify: false)).mock! }
    end

    desc 'version', 'Версия forge'
    def version = puts("forge #{Forge::VERSION}")

    private

    def guarded
      yield
    rescue Forge::Error => e
      raise if options[:debug]

      warn "error: #{e.message}"
      exit e.class.exit_code
    end
  end
end
