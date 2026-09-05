# frozen_string_literal: true

require 'forge/web/presenters'
require 'forge/web/overview'

RSpec.describe Forge::Web::Presenters do
  it 'highlights ruby with line numbers and escapes html' do
    html = described_class.ruby("class A < B\n  x = 'a<b' # note\nend\n")
    expect(html).to include('<td class="ln">1</td>', '<span class="t-k">class</span>', '<span class="t-C">A</span>',
                            '<span class="t-s">&#39;a&lt;b&#39;</span>', '<span class="t-c"># note</span>')
  end

  it 'renders markdown headings, tables, lists, fences and inline marks' do
    md = "# T\n\n## S\n\n| a | b |\n|---|---|\n| `x` | **y** |\n\n- one\n- two\n\n```\ncode\n```\n\n> q\n"
    html = described_class.markdown(md)
    expect(html).to include('<h2>T</h2>', '<h3>S</h3>', '<th>a</th>', '<td><code>x</code></td>', '<td><b>y</b></td>',
                            '<li>one</li>', '<pre>code</pre>', '<blockquote>q</blockquote>')
  end

  it 'renders json as a collapsible tree and falls back on invalid json' do
    html = described_class.json_tree('{"a":{"b":[1,"x"]},"c":null}')
    expect(html).to include('<details open>', '<span class="jk">a</span> <span class="jm">{1}</span>', '[2]',
                            '<span class="jn">1</span>', '<span class="js">&quot;x&quot;</span>')
    expect(described_class.json_tree('nope')).to eq('<pre>nope</pre>')
  end

  describe Forge::Web::Overview do
    let(:overview) do
      spec = Forge::IR::Builder.build(Forge::Loader.load('examples/specs/novapay.yaml'))
      findings = Forge::Analyzers::Runner.run(spec, rules: Forge::Rules.load)
      described_class.from(Forge::Report.json(spec, findings))
    end

    it 'summarises roles, auth and statuses' do
      expect(overview.endpoints.map { |e| [e['role'], e['title']] }).to include(['create', 'Создание выплаты'])
      expect([overview.confidence_class(0.95), overview.confidence_class(0.6)]).to eq(%w[ok warn])
      expect(overview.auth_line).to include('API key', 'X-API-Key')
      expect(overview.status_groups.to_h['approved']).to eq(['completed'])
    end

    it 'summarises signature, amount and warnings' do
      expect(overview.signature_line).to include('X-NovaPay-Signature', 'HMAC-SHA256', 'hex')
      expect(overview.amount_line).to include('минорные единицы ×100', 'минимум 1000', 'RUB')
      expect(overview.warnings.keys).to contain_exactly('warn', 'info')
    end
  end
end
