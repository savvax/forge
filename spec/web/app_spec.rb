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

  it 'runs the generated spec and e2e on demand' do
    id = create_run
    client.post("/runs/#{id}/spec")
    client.post("/runs/#{id}/e2e")
    page = client.get("/runs/#{id}").body
    expect(page).to include('examples, 0 failures', 'operation approved ✓')
  end

  it 'rejects examples outside examples/ and unknown runs' do
    res = client.post('/runs', params: { 'example' => '../Gemfile' })
    expect(res.body).to include('inside examples/')
    expect(client.get('/runs/nope').status).to eq(404)
    expect(client.get('/runs/../x/files/a').status).to eq(404)
  end

  it 'deletes a run' do
    id = create_run('verify' => '0')
    expect(client.post("/runs/#{id}/delete").status).to eq(303)
    expect(client.get("/runs/#{id}").status).to eq(404)
  end
end
