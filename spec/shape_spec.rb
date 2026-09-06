# frozen_string_literal: true

# Ввод пользователя никогда не должен ронять конвейер: битая структура → SpecError с pointer,
# всё прочее неожиданное → InternalError (exit 2), но не NoMethodError/TypeError наружу.
require 'forge/generate_command'

RSpec.describe Forge::Shape do
  head = "openapi: 3.0.3\ninfo: {title: Fz, version: '1'}\n"
  post_op = "    post:\n      responses: {'200': {description: ok}}\n"
  let(:base) { "openapi: 3.0.3\ninfo: {title: Fz, version: '1'}\n" }
  let(:op) { "    post:\n      responses: {'200': {description: ok}}\n" }

  def load_text(text, ext: 'yaml')
    path = "tmp/hostile.#{ext}"
    File.binwrite(path, text)
    Forge::Loader.load(path)
  end

  def generate(text)
    path = 'tmp/hostile.yaml'
    File.binwrite(path, text)
    Forge::GenerateCommand.new(spec: path, out: 'tmp/hostile_out', force: true, verify: false, format: 'json',
                               include_paths: []).run
  end

  describe Forge::Loader do
    {
      'ruby object tag' => ["openapi: 3.0.3\ninfo: !ruby/object:Object {}\npaths: {/p: {}}\n", 'cannot parse'],
      'unknown alias' => ["openapi: 3.0.3\ninfo: *nope\npaths: {/p: {}}\n", 'cannot parse'],
      'paths is a string' => ["#{head}paths: hello\n", 'no paths'],
      'path item is a string' => ["#{head}paths:\n  /p: hello\n", 'expected object, got string at #/paths/~1p'],
      'operation is a string' => ["#{head}paths:\n  /p:\n    post: hi\n", 'at #/paths/~1p/post'],
      'responses is a string' => ["#{head}paths:\n  /p:\n    post:\n      responses: nope\n",
                                  'expected object, got string at #/paths/~1p/post/responses'],
      'responses is an array' => ["#{head}paths:\n  /p:\n    post:\n      responses: [1]\n", 'got array'],
      'response is a string' => ["#{head}paths:\n  /p:\n    post:\n      responses: {'200': ok}\n",
                                 'at #/paths/~1p/post/responses/200'],
      'parameters is a hash' => ["#{head}paths:\n  /p:\n    post:\n      parameters: {a: 1}\n      responses: {}\n",
                                 'expected array, got object at #/paths/~1p/post/parameters'],
      'parameter is a string' => ["#{head}paths:\n  /p:\n    parameters: [x]\n#{post_op}",
                                  'at #/paths/~1p/parameters/0'],
      'parameter is null' => ["#{head}paths:\n  /p:\n    parameters: [null]\n#{post_op}", 'got null'],
      'content is a string' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: nope}\n",
                                'at #/paths/~1p/post/requestBody/content'],
      'properties is an array' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                                   "{schema: {properties: [a]}}}}\n", 'expected object, got array'],
      'property is a number' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                                 "{schema: {properties: {amount: 5}}}}}\n",
                                 'got number at #/paths/~1p/post/requestBody/content/application~1json/schema'],
      'enum is a number' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                             "{schema: {properties: {a: {enum: 5}}}}}}\n", 'expected array, got number'],
      'minimum is a string' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                                "{schema: {properties: {a: {minimum: nope}}}}}}\n", 'expected number, got string'],
      'info is a string' => ["openapi: 3.0.3\ninfo: hello\npaths:\n  /p:\n#{post_op}",
                             'expected object, got string at #/info'],
      'servers is a string' => ["#{head}servers: hello\npaths:\n  /p:\n#{post_op}",
                                'expected array, got string at #/servers'],
      'server is null' => ["#{head}servers: [null]\npaths:\n  /p:\n#{post_op}", 'got null at #/servers/0'],
      'server variables is a string' => ["#{head}servers: [{url: x, variables: nope}]\npaths:\n  /p:\n#{post_op}",
                                         'at #/servers/0/variables'],
      'security is a string' => ["#{head}security: nope\npaths:\n  /p:\n#{post_op}",
                                 'expected array, got string at #/security'],
      'security scope is a number' => ["#{head}security: [{a: 5}]\npaths:\n  /p:\n#{post_op}", 'at #/security/0/a'],
      'components is a string' => ["#{head}components: nope\npaths:\n  /p:\n#{post_op}", 'at #/components'],
      'schemas is a string' => ["#{head}components: {schemas: nope}\npaths:\n  /p:\n#{post_op}",
                                'at #/components/schemas'],
      'webhooks is a string' => ["#{head}webhooks: nope\npaths:\n  /p:\n#{post_op}",
                                 'at #/webhooks'],
      'callbacks is a string' => ["#{head}paths:\n  /p:\n    post:\n      callbacks: nope\n      responses: {}\n",
                                  'at #/paths/~1p/post/callbacks'],
      'headers is a string' => ["#{head}paths:\n  /p:\n    post:\n      responses: {'200': {headers: nope}}\n",
                                'at #/paths/~1p/post/responses/200/headers'],
      'examples is a string' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                                 "{examples: nope}}}\n", 'at #/paths/~1p/post/requestBody/content/application~1json'],
      'nested too deep' => ["#{head}paths:\n  /p:\n    post:\n      requestBody: {content: {application/json: " \
                            "{schema: #{'{properties: {a: ' * 5000}{}#{'}}' * 5000}}}}\n", 'nested too deep']
    }.each do |name, (text, message)|
      it "#{name} → SpecError '#{message}'" do
        expect { load_text(text) }.to raise_error(Forge::SpecError, Regexp.new(Regexp.escape(message)))
      end
    end

    it 'tolerates null path items, operations and bodies (treated as absent)' do
      text = "#{base}paths:\n  /p:\n  /q:\n    post:\n  /r:\n    post:\n      requestBody:\n      responses: {}\n"
      doc = load_text(text)
      expect(Forge::IR::Builder.build(doc).endpoints.map(&:path)).to eq(['/q', '/r'])
    end

    it 'stringifies non-string keys (200:, null:, true:)' do
      doc = load_text("#{base}5: x\nnull: y\npaths:\n  /p:\n    post:\n      responses: {200: {description: ok}}\n")
      expect(doc.keys).to include('5', '')
      expect(doc.dig('paths', '/p', 'post', 'responses').keys).to eq(['200'])
    end

    it 'treats a non-string $ref as unresolved instead of raising' do
      doc = load_text("#{base}paths:\n  /p:\n    post:\n      requestBody: {$ref: 5}\n      responses: {}\n")
      expect(doc.dig('paths', '/p', 'post', 'requestBody')).to eq('x-forge-unresolved' => '5')
    end

    it 'passes x-extensions through without shape checks' do
      doc = load_text("#{base}components: {x-forge: 5}\npaths:\n  /p:\n    x-role: 5\n#{op}")
      expect(doc.dig('components', 'x-forge')).to eq(5)
    end

    it 'still resolves and generates the reference spec byte-identically (golden covers the rest)' do
      expect(described_class.load('examples/specs/novapay.yaml').dig('info', 'title')).to eq('NovaPay Payout API')
    end
  end

  describe Forge::GenerateCommand do
    it 'turns an unexpected exception into InternalError (exit 2) that keeps the cause for --debug' do
      allow(Forge::Analyzers::Runner).to receive(:run).and_raise(NoMethodError, "undefined method `x' for nil")
      expect { generate("#{base}paths:\n  /p:\n#{op}") }.to raise_error(Forge::InternalError) do |e|
        expect(e.message).to include('internal error: NoMethodError', 'hint:')
        expect(e.cause).to be_a(NoMethodError)
        expect(e.class.exit_code).to eq(2)
      end
    end

    it 'lets SpecError through untouched' do
      expect { generate("#{base}paths: {}\n") }.to raise_error(Forge::SpecError, /no paths/)
    end
  end

  describe Forge::Plan::Overrides do
    def overrides(text)
      File.write('tmp/hostile.yml', text)
      described_class.load('tmp/hostile.yml')
    end

    {
      'ruby tag' => ["!ruby/object:Object {}\n", 'cannot parse'],
      'broken yaml' => ["a: [\n", 'cannot parse'],
      'section is a string' => ["statuses: nope\n", "overrides key 'statuses' must be a mapping"],
      'section is an array' => ["endpoints: [1]\n", "overrides key 'endpoints' must be a mapping"],
      'multiplier is a string' => ["amount: {unit: minor, multiplier: '100'}\n",
                                   "'amount.multiplier' must be a number"],
      'required_if is a string' => ["fields: {x: {required_if: nope}}\n", "'fields.x.required_if' must be a mapping"]
    }.each do |name, (text, message)|
      it "#{name} → SpecError '#{message}'" do
        expect { overrides(text) }.to raise_error(Forge::SpecError, Regexp.new(Regexp.escape(message)))
      end
    end
  end

  describe Forge::Plan::Naming do
    it 'caps the name, prefixes a leading digit and falls back to provider for garbage' do
      expect(described_class.from_provider('a' * 300)[:name].size).to eq(60)
      expect(described_class.from_provider('123 pay')[:class_name]).to eq('P123PayService')
      expect(described_class.from_provider('!!!')[:name]).to eq('provider')
    end
  end
end
