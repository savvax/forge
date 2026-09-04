# frozen_string_literal: true

require 'fileutils'
require_relative 'service'
require_relative 'service_spec'
require_relative 'fixtures'
require_relative 'integration_doc'
require_relative 'mock_server'

module Forge
  module Renderers
    # Все рендереры по порядку ТЗ → файлы в out_dir. Возвращает [{label:, path:}].
    class Runner
      STEPS = [['service', Service], ['integration guide', IntegrationDoc], ['test fixtures', Fixtures],
               ['service spec', ServiceSpec]].freeze
      HELPER = File.expand_path('../generated_spec_helper.rb', __dir__)

      def self.render(plan, out_dir:, templates_dir: nil, force: false)
        new(plan, out_dir, templates_dir, force).render
      end

      def self.steps = STEPS + [['mock server', MockServer]]

      def initialize(plan, out_dir, templates_dir, force)
        @plan = plan
        @out_dir = out_dir
        @templates_dir = templates_dir
        @force = force
      end

      def render
        prepare_dir!
        files = self.class.steps.map do |label, klass|
          renderer = klass.new(@plan, templates_dir: @templates_dir)
          { label: label, path: write(renderer.filename, renderer.render) }
        end
        FileUtils.cp(HELPER, File.join(@out_dir, 'generated_spec_helper.rb'))
        files
      end

      private

      def prepare_dir!
        if File.directory?(@out_dir) && !Dir.empty?(@out_dir) && !@force
          raise GenerationError.new("output directory is not empty: #{@out_dir}", hint: 'pass --force to overwrite')
        end

        FileUtils.mkdir_p(@out_dir)
      end

      def write(name, content)
        path = File.join(@out_dir, name)
        File.write(path, content)
        path
      end
    end
  end
end
