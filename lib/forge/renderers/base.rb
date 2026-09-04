# frozen_string_literal: true

require 'erb'

module Forge
  module Renderers
    # Общее для рендереров: поиск шаблона (--templates-dir → templates/), ERB с trim_mode '-', нормализация.
    class Base
      DEFAULT_DIR = File.expand_path('../../../templates', __dir__)

      attr_reader :plan

      def initialize(plan, templates_dir: nil)
        @plan = plan
        @templates_dir = templates_dir
      end

      def render = normalize(ERB.new(template_source, trim_mode: '-').result(binding))

      def template_name = raise(NotImplementedError)
      def filename = raise(NotImplementedError)

      private

      def template_source
        candidates = [@templates_dir && File.join(@templates_dir, template_name), File.join(DEFAULT_DIR, template_name)]
        path = candidates.compact.find { |p| File.exist?(p) }
        unless path
          raise GenerationError.new("template not found: #{template_name}",
                                    hint: "looked in #{candidates.compact.join(', ')}")
        end

        File.read(path)
      end

      def partial(name) = ERB.new(File.read(File.join(DEFAULT_DIR, name)), trim_mode: '-').result(binding)

      # Не больше одной пустой строки подряд, ровно один \n в конце.
      def normalize(text) = "#{text.gsub(/\n{3,}/, "\n\n").rstrip}\n"
    end
  end
end
