# frozen_string_literal: true

require 'json'
require_relative 'report_lines'

module Forge
  # Текстовый и JSON-отчёт по findings (docs/OUTPUT_FORMAT.md § 6). Длинные списки сворачиваются.
  class Report
    FOLD = 10
    LEVELS = { warn: 'WARN', unsupported: 'UNSUPPORTED', info: 'INFO' }.freeze

    def self.text(spec, findings, plan: nil) = new(spec, findings, plan).text
    def self.json(spec, findings, plan: nil, exit_code: 0) = new(spec, findings, plan).json(exit_code)

    def initialize(spec, findings, plan)
      @spec = spec
      @findings = findings
      @plan = plan
      @lines = ReportLines.new(spec, findings)
    end

    def text
      [@lines.header, @lines.endpoints, @lines.auth, @lines.statuses, @lines.errors, @lines.webhook_signature,
       @lines.webhook_events, @lines.amount, @lines.fields, *warning_sections, done].flatten.compact.join("\n")
    end

    def warnings = @findings.values.flat_map(&:warnings)

    SECTIONS = { auth: :auth, statuses: :statuses, errors: :errors, webhook: :webhooks, amount: :amount,
                 fields: :fields }.freeze

    def json(exit_code)
      sections = SECTIONS.transform_values { |key| plain(@findings[key].value) }
      spec = { openapi: @spec.openapi_version, title: @spec.title, version: @spec.version, source: @spec.source_path }
      warns = warnings.map { |w| plain(w.to_h) }
      JSON.pretty_generate({ spec: spec, endpoints: @lines.endpoint_rows, **sections, warnings: warns,
                             exit_code: exit_code })
    end

    private

    def warning_sections
      LEVELS.filter_map do |level, label|
        items = warnings.select { |w| w.level == level }
        next if items.empty?

        title = { warn: 'Warnings', unsupported: 'Unsupported', info: 'Info' }[level]
        ["#{title} (#{items.size}):", *fold(items.map { |w| warning_lines(label, w) })]
      end
    end

    def warning_lines(label, warning)
      lines = [format('  %<level>-11s  %<code>-26s %<message>s', level: label, code: warning.code,
                                                                 message: warning.message)]
      lines << "        hint: #{warning.hint}" if warning.hint
      lines.join("\n")
    end

    def fold(items)
      return items if items.size <= FOLD

      items.first(FOLD) + ["  … and #{items.size - FOLD} more (see --format json)"]
    end

    def done
      counts = warnings.group_by(&:level).transform_values(&:size)
      "Done: #{counts.fetch(:warn, 0)} warnings, #{counts.fetch(:unsupported, 0)} unsupported. Exit 0."
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
