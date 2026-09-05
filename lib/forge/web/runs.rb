# frozen_string_literal: true

module Forge
  module Web
    # Один прогон = каталог tmp/web/<id>/ с input/ (спека, overrides), out/ (вывод generate), meta.json.
    # Состояние только на диске: перезапуск сервера ничего не теряет, секретов нет.
    class Runs
      MAX_SPEC_BYTES = 20 * 1024 * 1024

      class << self
        attr_accessor :root

        def create(params)
          id = "#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(3)}"
          run = new(id)
          run.prepare(params)
          run.generate
          run
        end

        def find(id)
          return nil unless id.to_s.match?(/\A[\w-]+\z/) && File.exist?(File.join(root, id, 'meta.json'))

          new(id)
        end

        def recent(limit)
          Dir[File.join(root, '*', 'meta.json')].reverse.first(limit).map do |m|
            new(File.basename(File.dirname(m)))
          end
        end

        def delete(id) = FileUtils.rm_rf(File.join(root, id))
      end

      attr_reader :id

      def initialize(id)
        @id = id
        @dir = File.join(self.class.root, id)
      end

      def meta = @meta ||= (File.exist?(meta_path) ? JSON.parse(File.read(meta_path)) : {})
      def provider = meta['provider'] || 'provider'
      def out_dir = File.join(@dir, 'out')
      def spec_path = meta['spec']
      def spec_name = meta['spec_name'] || File.basename(spec_path.to_s)
      def files = Dir[File.join(out_dir, '*')].map { |f| File.basename(f) }
      def file(name) = (path = File.join(out_dir, File.basename(name))) && File.file?(path) ? path : nil

      def report
        text = read('out/report.txt')
        error = meta['error'].to_s
        [text, (error.empty? ? nil : "error: #{error}")].compact.join("\n\n")
      end

      def report_json = read('report.json') || '{}'
      def step_output(name) = read("#{name}.log")
      def exit_code = meta['exit_code']

      # Сохраняет входные файлы и параметры команды.
      def prepare(params)
        FileUtils.mkdir_p(File.join(@dir, 'input'))
        spec = save_upload(params[:spec], params[:spec_text], params[:example], 'spec')
        raise ArgumentError, 'spec is required: upload a file, pick an example or paste the text' unless spec

        overrides = save_upload(params[:overrides], params[:overrides_text], params[:overrides_example], 'overrides')
        write_meta('spec' => spec, 'spec_name' => @spec_name, 'overrides' => overrides,
                   'provider_name' => blank_to_nil(params[:provider]),
                   'include_paths' => params[:include_paths].to_s.split(/[\s,]+/).reject(&:empty?),
                   'strict' => params[:strict] == '1', 'verify' => params[:verify] != '0',
                   'created_at' => Time.now.utc.iso8601)
      end

      # bin/forge generate тем же кодом, что и CLI; stdout → report, ошибки → meta.error.
      # Один прогон: stdout в формате json → report.json; report.txt (текст того же прогона) пишет сам GenerateCommand.
      def generate
        code, json = capture { GenerateCommand.new(generate_options).run }
        File.write(File.join(@dir, 'report.json'), json)
        write_meta(meta.merge('exit_code' => code, 'provider' => provider_from_files))
      rescue Forge::Error => e
        write_meta(meta.merge('exit_code' => e.class.exit_code, 'error' => e.message,
                              'provider' => provider_from_files))
      end

      def generate_options
        { spec: spec_path, out: out_dir, overrides: meta['overrides'], provider: meta['provider_name'],
          include_paths: meta['include_paths'], strict: meta['strict'], verify: meta['verify'],
          force: true, format: 'json', templates_dir: nil }
      end

      def exec_step(name)
        cmd = name == :spec ? spec_command : e2e_command
        out, status = Open3.capture2e(*cmd, chdir: project_root)
        File.write(File.join(@dir, "#{name}.log"), "$ #{cmd.join(' ')}\n#{out}\n[exit #{status.exitstatus}]\n")
      end

      def tar
        io = StringIO.new
        Gem::Package::TarWriter.new(io) do |tar|
          files.each do |name|
            data = File.read(File.join(out_dir, name))
            tar.add_file_simple("#{provider}/#{name}", 0o644, data.bytesize) { |f| f.write(data) }
          end
        end
        io.string
      end

      private

      def project_root = File.expand_path('../../..', __dir__)
      def meta_path = File.join(@dir, 'meta.json')
      def read(rel) = (p = File.join(@dir, rel)) && File.exist?(p) ? File.read(p) : nil
      def write_meta(hash) = File.write(meta_path, JSON.pretty_generate(hash)).then { @meta = hash }
      def blank_to_nil(value) = value.to_s.strip.empty? ? nil : value.to_s.strip

      def provider_from_files
        Dir[File.join(out_dir, '*_service.rb')].map { |f| File.basename(f, '_service.rb') }.first || 'provider'
      end

      def save_upload(upload, text, example, kind)
        data, name = upload_source(upload, text, example, kind)
        return nil unless data

        @spec_name = name if kind == 'spec'

        if data.bytesize > MAX_SPEC_BYTES
          raise ArgumentError,
                "#{kind}: file too large (max #{MAX_SPEC_BYTES / 1024 / 1024} MB)"
        end

        ext = File.extname(name)
        path = File.join(@dir, 'input', "#{kind}#{ext.empty? ? '.yaml' : ext}")
        File.write(path, data)
        path
      end

      def upload_source(upload, text, example, kind)
        return [upload[:tempfile].read, upload[:filename]] if upload.respond_to?(:[]) && upload[:tempfile]
        return [text, "#{kind}.yaml"] unless text.to_s.strip.empty?
        return [File.read(example_path(example)), File.basename(example)] unless example.to_s.empty?

        nil
      end

      # Примеры только из каталога проекта — никаких произвольных путей с диска.
      def example_path(rel)
        path = File.expand_path(rel, project_root)
        allowed = path.start_with?(File.join(project_root, 'examples', ''))
        raise ArgumentError, 'example must be inside examples/' unless allowed && File.file?(path)

        path
      end

      def capture
        out = StringIO.new
        old = $stdout
        $stdout = out
        code = yield
        [code, out.string]
      ensure
        $stdout = old
      end

      def spec_command
        spec = Dir[File.join(out_dir, '*_service_spec.rb')].first
        ['bundle', 'exec', 'rspec', '--options', '/dev/null', '-I', 'lib', '-I', out_dir, spec.to_s]
      end

      def e2e_command
        cmd = ['bin/e2e', spec_path]
        cmd += ['--overrides', meta['overrides']] if meta['overrides']
        cmd
      end
    end
  end
end
