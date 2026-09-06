# frozen_string_literal: true

require 'rack/mock'
require 'forge/web/app'

RSpec.describe Forge::Web::App do
  let(:app) { described_class }
  let(:client) { Rack::MockRequest.new(app) }

  before { Forge::Web::Runs.root = 'tmp/web_spec' }

  def create_run(extra = {})
    form = { 'example' => 'examples/specs/novapay.yaml' }.merge(extra)
    res = client.post('/runs', params: form)
    expect(res.status).to eq(303), res.body
    res.headers['Location'][%r{/runs/([\w-]+)}, 1]
  end

  it 'renders the form with examples' do
    res = client.get('/')
    expect(res.status).to eq(200)
    expect(res.body).to include('novapay.yaml', 'cardpay.yml', 'Analyze + Generate')
  end

  it 'creates a run from an example spec, shows report and files, serves json and tar' do
    id = create_run
    page = client.get("/runs/#{id}").body
    expect(page).to include('Parsing spec... ok', 'novapay_service.rb', 'Done: 7 files', 'Эндпоинты и роли',
                            'Создание выплаты', 'X-NovaPay-Signature', 'Поля запроса')
    expect(page).to include('<span class="t-k">class</span>', '<h3>Авторизация</h3>',
                            '<span class="jk">create_request</span>')
    expect(client.get("/runs/#{id}/files/novapay_service.rb").body).to include('class NovapayService < BaseService')
    expect(JSON.parse(client.get("/runs/#{id}/report.json").body)['exit_code']).to eq(0)
    expect(client.get("/runs/#{id}/download.tar").body).to include('novapay/fixtures.json')
  end

  it 'applies overrides, --provider and --strict from the form' do
    id = create_run('example' => 'examples/specs/cardpay.yaml', 'overrides_example' => 'examples/overrides/cardpay.yml',
                    'provider' => 'Card Pay', 'strict' => '1', 'verify' => '0')
    page = client.get("/runs/#{id}").body
    expect(page).to include('card_pay_service.rb', 'Exit 0', '0 warnings')
  end

  it 'accepts a pasted spec and shows Forge errors on the run page without a stacktrace' do
    id = create_run('example' => '', 'spec_text' => "openapi: 3.0.3\ninfo: {title: X, version: '1'}\npaths: {}\n")
    page = client.get("/runs/#{id}").body
    expect(page).to include('no paths', 'hint:', 'exit-1')
    expect(page).not_to include('.rb:')
  end

  it 'rejects a form without any spec source with a readable message' do
    res = client.post('/runs', params: { 'example' => '', 'spec_text' => '' })
    expect(res.status).to eq(200)
    expect(res.body).to include('spec is required')
    expect(res.body).not_to include('.rb:')
  end

  it 'runs the generated spec and e2e on demand and opens the «Запуски» tab' do
    id = create_run
    expect(client.post("/runs/#{id}/spec").headers['Location']).to end_with("/runs/#{id}?tab=runs#spec")
    client.post("/runs/#{id}/e2e")
    page = client.get("/runs/#{id}?tab=runs").body
    expect(page).to include('examples, 0 failures', 'operation approved ✓', 'id="t-runs" checked')
    expect(page).not_to include('id="t-overview" checked') # иначе вкладка с выводом остаётся скрытой CSS
    expect(client.get("/runs/#{id}").body).to include('id="t-overview" checked')
  end

  it 'rejects examples outside examples/ and unknown runs' do
    res = client.post('/runs', params: { 'example' => '../Gemfile' })
    expect(res.body).to include('inside examples/')
    expect(client.get('/runs/nope').status).to eq(404)
    expect(client.get('/runs/../x/files/a').status).to eq(404)
  end

  it 'never answers 500 to malformed form params (wrong types, null bytes, overlong names)' do
    forms = [{ 'spec' => 'hello' }, { 'spec' => %w[a b] }, { 'spec' => { 'tempfile' => 'x', 'filename' => 'y' } },
             { 'spec_text' => %w[a b] }, { 'spec_text' => { 'a' => 'b' } }, { 'example' => %w[examples/specs/x.yaml] },
             { 'example' => { 'a' => 'b' } }, { 'example' => 'examples/specs/novapay.yaml', 'overrides' => 'x' },
             { 'example' => 'examples/specs/novapay.yaml', 'overrides_example' => ['a'] }]
    forms.each do |form|
      res = client.post('/runs', params: form)
      expect([200, 303]).to include(res.status), "#{form.inspect}: #{res.status} #{res.body[0, 200]}"
    end
    id = create_run('provider' => 'a' * 300, 'verify' => '0')
    expect(client.get("/runs/#{id}").body).to include("#{'a' * 60}_service.rb")
    expect(client.get("/runs/#{id}/files/%00").status).to eq(404)
  end

  it 'shows a Forge error page, not a stacktrace, for a spec that breaks the pipeline' do
    text = "openapi: 3.0.3\ninfo: {title: X, version: '1'}\npaths:\n  /p:\n    post:\n      responses: nope\n"
    id = create_run('example' => '', 'spec_text' => text)
    page = client.get("/runs/#{id}").body
    expect(page).to include('expected object, got string at #/paths/~1p/post/responses', 'exit-1')
    expect(page).not_to include('.rb:')
  end

  it 'renders the generic error page instead of Sinatra 500 on an unexpected exception' do
    allow(Forge::Web::Runs).to receive(:recent).and_raise(Errno::EACCES, 'tmp')
    res = client.get('/', 'rack.errors' => StringIO.new)
    expect(res.status).to eq(500)
    expect(res.body).to include('unexpected error', 'Permission denied')
    expect(res.body).not_to include('Internal Server Error')
  end

  it 'survives a corrupted meta.json on disk' do
    id = create_run('verify' => '0')
    File.write("tmp/web_spec/#{id}/meta.json", 'not json')
    expect(client.get("/runs/#{id}").status).to eq(200)
    File.write("tmp/web_spec/#{id}/meta.json", '[]')
    expect(client.get("/runs/#{id}").status).to eq(200)
  end

  it 'skips the rspec step with a readable log when generation produced no spec' do
    id = create_run('example' => '', 'spec_text' => "openapi: 3.0.3\ninfo: {title: X, version: '1'}\npaths: {}\n")
    expect(client.post("/runs/#{id}/spec").status).to eq(303)
    expect(Forge::Web::Runs.new(id).step_output('spec')).to include('no generated spec')
  end

  it 'keeps report.json intact for concurrent runs (no global $stdout capture under Puma threads)' do
    runs = Array.new(3) { Thread.new { Forge::Web::Runs.create(example: 'examples/specs/novapay.yaml', verify: '0') } }
                .map(&:value)
    runs.each do |run|
      expect(JSON.parse(run.report_json)['endpoints'].size).to eq(5), run.id
      expect(client.get("/runs/#{run.id}").status).to eq(200)
    end
  end

  it 'deletes a run' do
    id = create_run('verify' => '0')
    expect(client.post("/runs/#{id}/delete").status).to eq(303)
    expect(client.get("/runs/#{id}").status).to eq(404)
  end
end
