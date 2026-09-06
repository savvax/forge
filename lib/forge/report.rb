# frozen_string_literal: true

require 'json'
require_relative 'report_lines'

module Forge
  # Текстовый и JSON-отчёт по findings (docs/OUTPUT_FORMAT.md § 6). Длинные списки сворачиваются.
  # generation: {steps: [label], verify: 'ok (…)' | 'skipped', outputs: [path]} — секции команды generate.
  class Report
    FOLD = 10
    LEVELS = { warn: 'WARN', unsupported: 'UNSUPPORTED', info: 'INFO' }.freeze
    TITLES = { warn: 'Warnings', unsupported: 'Unsupported', info: 'Info' }.freeze
    SECTIONS = { auth: :auth, statuses: :statuses, errors: :errors, webhook: :webhooks, amount: :amount,
                 fields: :fields }.freeze

    def self.text(spec, findings, generation: nil) = new(spec, findings).text(generation)

    def self.json(spec, findings, exit_code: 0, generation: nil) = new(spec, findings).json(exit_code, generation)

    def initialize(spec, findings)
      @spec = spec
      @findings = findings
      @lines = ReportLines.new(spec, findings)
    end

    def text(generation = nil)
      [@lines.header, @lines.endpoints, @lines.auth, @lines.statuses, @lines.errors, @lines.webhook_signature,
       @lines.webhook_events, @lines.amount, @lines.fields, *generation_lines(generation), *warning_sections,
       done(generation)].flatten.compact.join("\n")
    end

    def warnings = @findings.values.flat_map(&:warnings)

    def json(exit_code, generation = nil)
      sections = SECTIONS.transform_values { |key| plain(@findings[key].value) }
      sections[:outputs] = generation[:outputs] if generation
      spec = { openapi: @spec.openapi_version, title: @spec.title, version: @spec.version, source: @spec.source_path }
      warns = warnings.map { |w| plain(w.to_h) }
      JSON.pretty_generate({ spec: spec, endpoints: @lines.endpoint_rows, **sections, warnings: warns,
                             exit_code: exit_code })
    end

    private

    def generation_lines(generation)
      return [] unless generation

      generation[:steps].map { |label| "Generating #{label}..." } +
        ["Verifying generated code... #{generation[:verify]}", 'Output:'] + generation[:outputs].map { |p| "  #{p}" }
    end

    def warning_sections
      LEVELS.filter_map do |level, label|
        items = warnings.select { |w| w.level == level }
        next if items.empty?

        ["#{TITLES[level]} (#{items.size}):", *fold(items.map { |w| warning_lines(label, w) })]
      end
    end

    def warning_lines(label, warning)
      values = { level: label, code: warning.code, message: warning.message }
      lines = [format('  %<level>-11s  %<code>-26s %<message>s', values)]
      lines << "        hint: #{warning.hint}" if warning.hint
      lines.join("\n")
    end

    def fold(items)
      return items if items.size <= FOLD

      items.first(FOLD) + ["  … and #{items.size - FOLD} more (see --format json)"]
    end

    def done(generation)
      counts = warnings.group_by(&:level).transform_values(&:size)
      files = generation ? "#{generation[:outputs].size} files, " : ''
      code = generation&.fetch(:exit_code, 0) || 0
      totals = "#{counts.fetch(:warn, 0)} warnings, #{counts.fetch(:unsupported, 0)} unsupported"
      "Done: #{files}#{totals}. Exit #{code}.#{done_suffix(generation, code)}"
    end

    def done_suffix(generation, code)
      return ' (generated spec failed, see the error above)' if generation&.dig(:verify).to_s.start_with?('FAILED')

      code.zero? ? '' : ' (--strict: warnings present, output still generated)'
    end

    # Data/Symbol/Endpoint/Schema → JSON-дружественные структуры.
    def plain(node)
      case node
      when IR::Endpoint then { method: node.method, path: node.path, operation_id: node.operation_id }
      when IR::Schema then { type: node.type, enum: node.enum }.compact
      when Data then plain(node.to_h)
      when Hash then node.to_h { |k, v| [k.to_s, plain(v)] }
      else plain_scalar(node)
      end
    end

    def plain_scalar(node)
      case node
      when Array then node.map { |v| plain(v) }
      when Symbol then node.to_s
      else node
      end
    end
  end
end
