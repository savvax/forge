# frozen_string_literal: true

# rake fuzz:web — враждебные спеки, overrides, параметры формы и URL против Forge::Web::App (in-process,
# Rack::MockRequest). Падение = исключение или ответ 5xx. Корпус — spec/fuzz/corpus/*.yml; случаи, которые
# нельзя записать в YAML (байты, размер, глубина), генерируются в Generated.
require 'rack/mock'
require 'rack/multipart'
require 'yaml'
require 'json'
require 'securerandom'
require_relative 'harness'
require_relative 'web_routes'
require_relative '../../lib/forge/web/app'

module Fuzz
  class Web
    include WebRoutes

    CORPUS = File.join(__dir__, 'corpus')
    BASE = "openapi: 3.0.3\ninfo: {title: Fz, version: '1'}\n"
    OP = "    post:\n      responses: {'200': {description: ok}}\n"

    # Случаи вне YAML-корпуса: бинарные байты, BOM, CRLF, размер и глубина.
    module Generated
      module_function

      def specs
        json_bomb = "#{'{"type":"object","properties":{"a":' * 90}{}#{'}}' * 90}"
        { 'empty' => '', 'binary' => "\x00\x01\xff\xfePK\x03\x04".b,
          'bad_utf8' => "openapi: 3.0.3\ninfo: {title: \xff\xfeX, version: '1'}\npaths:\n  /p:\n#{OP}".b,
          'yaml_bom' => "\uFEFF#{BASE}paths:\n  /p:\n#{OP}",
          'crlf' => "#{BASE}paths:\n  /p:\n#{OP}".gsub("\n", "\r\n"),
          'yaml_huge_scalar' => "#{BASE}paths:\n  /p:\n    post:\n      description: '#{'x' * 2_000_000}'\n      " \
                                "responses: {'200': {description: ok}}\n",
          'nesting_deep' => "#{BASE}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                            "{schema: #{'{type: object, properties: {a: ' * 3000}{}#{'}}' * 3000}}}}\n",
          'ref_chain_long' => ref_chain(2000), 'many_ops' => many_ops(300), 'alias_bomb' => alias_bomb,
          'json_nested_bomb' => '{"openapi":"3.0.3","info":{"title":"X","version":"1"},"paths":{"/p":{"post":' \
                                '{"responses":{"200":{"description":"ok"}},"requestBody":{"content":' \
                                "{\"application/json\":{\"schema\":#{json_bomb}}}}}}}}" }
      end

      def ref_chain(size)
        schemas = (0...size).map { |i| "    S#{i}: {$ref: '#/components/schemas/S#{i + 1}'}\n" }.join
        "#{BASE}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: {schema: " \
          "{$ref: '#/components/schemas/S0'}}}}\n      responses: {}\ncomponents:\n  schemas:\n#{schemas}    " \
          "S#{size}: {type: object}\n"
      end

      def many_ops(size)
        "#{BASE}paths:\n#{(0...size).map { |i| "  /payouts#{i}:\n#{OP}" }.join}"
      end

      def alias_bomb
        levels = %w[a b c d e f].each_cons(2).map { |prev, cur| "#{cur}: &#{cur} [#{(["*#{prev}"] * 10).join(',')}]\n" }
        "#{BASE}a: &a [x,x,x,x,x,x,x,x,x,x]\n#{levels.join}paths:\n  /p:\n#{OP}"
      end
    end

    def initialize
      @h = Harness.new('web')
      @root = @h.workdir('web')
      @uploads = File.join(@root, 'uploads')
      FileUtils.mkdir_p(@uploads)
      Forge::Web::Runs.root = @root
      Forge::Web::App.set :raise_errors, true
      @client = Rack::MockRequest.new(Forge::Web::App)
    end

    def run
      corpus('specs').merge(Generated.specs).each { |name, text| @h.check("spec:#{name}") { spec_case(name, text) } }
      corpus('overrides').each { |name, text| @h.check("overrides:#{name}") { overrides_case(text) } }
      corpus('forms').each { |name, form| @h.check("form:#{name}") { form_case(form) } }
      route_cases
      @h.report!
    end

    private

    def corpus(name) = YAML.safe_load_file(File.join(CORPUS, "#{name}.yml"))

    def upload(text, name)
      path = File.join(@uploads, "#{SecureRandom.hex(4)}-#{name}")
      File.binwrite(path, text)
      Rack::Multipart::UploadedFile.new(path, 'text/plain', filename: name)
    end

    def post(path, form = {}) = @client.post(path, params: form)
    def get(path) = @client.get(path)

    # 2xx/3xx/4xx допустимы; 5xx и исключения — падение.
    def ok!(res, what)
      raise "#{what}: HTTP #{res.status} #{res.body[0, 200]}" if res.status >= 500

      res
    end

    def run_id(res) = res.status == 303 ? res.headers['Location'][%r{/runs/([\w-]+)}, 1] : nil

    def spec_case(name, text)
      ext = name.start_with?('json') ? 'json' : 'yaml'
      id = run_id(ok!(post('/runs', 'spec' => upload(text, "s.#{ext}"), 'verify' => '0'), 'POST /runs'))
      return unless id

      visit_run(id)
      Dir[File.join(@root, id, 'out', '*')].each { |f| ok!(get("/runs/#{id}/files/#{File.basename(f)}"), f) }
    end

    def visit_run(id)
      ['', '/report.json', '/download.tar', '?tab=runs'].each { |s| ok!(get("/runs/#{id}#{s}"), "GET run#{s}") }
    end

    def overrides_case(text)
      form = { 'spec' => upload(File.read(EXAMPLE), 'novapay.yaml'), 'overrides' => upload(text, 'o.yml'),
               'verify' => '0' }
      id = run_id(ok!(post('/runs', form), 'POST /runs'))
      visit_run(id) if id
    end

    def form_case(form)
      id = run_id(ok!(post('/runs', form), "POST /runs #{form.inspect[0, 80]}"))
      visit_run(id) if id
    end
  end
end

Fuzz::Web.new.run if $PROGRAM_NAME == __FILE__
