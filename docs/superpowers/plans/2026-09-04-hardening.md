# forge hardening — план исправления недостатков v1.0.0

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `bin/forge generate` не падает ни на одной OpenAPI-спеке: любая неожиданная ситуация — либо
осмысленный `Forge::Error` с exit 1–4, либо WARN/TODO в выводе; шесть спек из проверки 4.09 (Adyen Payout,
Adyen Webhooks, Adyen Transfers, PayPal Payouts, Raiffeisen SBP, ApiPay.kz) проходят `analyze` и `generate`
без стектрейсов, а документация совпадает с реальностью.

**Architecture:** Исправления идут по слоям конвейера `Load → IR → Analyze → Plan → Render → Verify → Report`
и не меняют его. Рендереры перестают предполагать непустые карты и заполненные источники (пустая карта →
`{}.freeze` + TODO, nil-источник → `nil, # TODO`). Анализаторы получают общий поиск по схеме (`SchemaSearch`),
нормализованное сравнение имён и явный порядок предпочтения auth. Path-параметры операций получают
источники (`PathSources`): последний параметр status/cancel — id выплаты, остальные — `credentials`.
CLI получает «последний рубеж»: любое не-Forge исключение → одна строка + hint, exit 70. Реальные спеки
проходят и `generate`, а не только `analyze`.

**Tech Stack:** Ruby 3.3, thor, erb, rspec, webmock, rubocop; никаких новых гемов.

**Spec:** Отчёты проверок в этой сессии (см. `docs/AUDIT_REPORT.md`, REQUIREMENTS.md § 4) и найденные дефекты:

| # | Дефект | Где | Задача |
|---|---|---|---|
| D1 | `aligned({})` → `nil + 2`: пустой `status_map`/`event_map` роняет `generate` (Adyen Payout, PayPal, Raiffeisen) | `lib/forge/renderers/service_view.rb:36` | T2 |
| D2 | `requisite_expr(nil)`: поле варианта `oneOf` без источника роняет `generate` (Adyen Transfers) | `lib/forge/renderers/service_payload.rb:38` | T3 |
| D3 | Не-Forge исключение печатает стектрейс без `--debug`, exit 1 неотличим от ошибки входа | `lib/forge/cli.rb:57` | T1 |
| D4 | Create-эндпоинт с path-параметром: в URL подставляется `provider_operation_id` (nil), spec красный (ApiPay) | `service_paths.rb:17`, `service_spec.rb:34` | T4 |
| D5 | Статус не найден, когда enum лежит в объекте `status.value` (Raiffeisen), на 2-м уровне `batch_header.batch_status` (PayPal) или в camelCase `resultCode` (Adyen) | `analyzers/statuses.rb` | T5 |
| D6 | Auth берёт первую схему из `security`: query-ключ вместо `X-API-Key` (Adyen Transfers), basic вместо apiKey (Adyen Payout); без `securitySchemes` — «not found», хотя есть header `Authorization` (Raiffeisen) | `analyzers/auth.rb` | T6 |
| D7 | `x-webhooks` (Redocly, Raiffeisen) не читается; спека только с `webhooks` даёт hint «declare at least one path» | `ir/builder.rb`, `loader.rb` | T7 |
| D8 | Контейнер реквизитов в camelCase (`bankAccount`) не распознаётся; вложенный контейнер (`counterparty.bankAccount`) рендерится в корень payload; enum типа реквизита (`iban|usLocal`) молча расходится с каноном | `field_walker.rb`, `fields.rb`, `service_payload.rb` | T3 |
| D9 | Подсказка `statuses.field: <path>` обещает ключ, который `OverridesEdits#statuses` трактует как маппинг статуса | `plan/overrides_edits.rb` | T2 |
| D10 | `rake real` гоняет только `analyze`; `generate` на реальных спеках ни разу не запускался | `Rakefile`, `spec/real_specs_spec.rb` | T8 |
| D11 | `templates/service.rb.erb` — 234 строки при планке < 200 | `templates/` | T9 |
| D12 | Документы расходятся с фактом: REQUIREMENTS (5 vs 6 записей, CardPay 8 WARN vs 5+4, `amount_unit`, `overrides.yml.example`, 8 vs 10 битых спек), AUDIT (`.mise.toml`), CLAUDE.md (`overrides.yml.example`), AUDIT_REPORT (61 vs 59 файлов) | `docs/`, `REQUIREMENTS.md`, `CLAUDE.md` | T10 |
| D13 | Тег `v1.0.0` стоит на коммит раньше HEAD и не запушен | git | T11 |

Сознательно **не** делаем в этом плане (в «Резерв» `docs/AGENT_TASKS.md`): `overrides.yml.example` как
отдельный файл (нужны структурированные hint во всех анализаторах — R6), маппинг сумм внутри массивов
(`items[].amount`, PayPal batch — R7), выбор варианта `oneOf` через overrides (R2), статус через POST (R3).

## Global Constraints

- Ruby 3.3, `# frozen_string_literal: true` в каждом `.rb`; без метапрограммирования; файлы < 200 строк,
  методы ≤ 20 строк (`.rubocop.yml`); `bundle exec rubocop` — 0 нарушений.
- Никаких новых гемов. Никаких сетевых вызовов при analyze/generate. Детерминизм вывода.
- Знание о провайдере не живёт в `lib/` (`rake guard:vendor`): слова `adyen`, `paypal`, `raiffeisen`, `kaspi`
  допустимы только в `spec/`, `examples/`, `docs/`.
- Golden `spec/golden/*` и снапшоты `spec/snapshots/*` для novapay/cardpay/swiftpay **не меняются** в T1–T9
  (это регрессионный контракт). Единственное осознанное обновление golden — T11 (номер версии в заголовках).
  Канон NovaPay: ровно 6 записей (3 WARN, 3 INFO) — `NOTES.md` D-06.
- Каждая задача заканчивается зелёным `bundle exec rake check` и коммитом `<module>: <what>` на английском,
  без трейлеров Co-Authored-By; в конце сообщения — строка `Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s`.
- Команды выполнять через `mise exec -- …` или после `eval "$(mise env -s zsh)"` (системный Ruby 2.6 не подходит).
- Порядок задач фиксирован: T2 и T3 зависят от T1 (тест на exit 70 использует их сценарии как регрессию),
  T4 зависит от T2 (шаблон spec), T8 — от T1–T7, T11 — последняя.

---

### Task 0: Корпус реальных спек и базовая линия

**Files:**
- Move: `adyen_payout_v68.yaml`, `adyen_webhooks_v1.yaml`, `paypal_payouts_v1.json`, `adyen_transfers_v4.yaml`,
  `raiffeisen_sbp_payout.yaml`, `apipay_kz_kaspi_openapi.yaml` (корень репозитория, untracked) → `examples/real/`
- Create: `tmp/baseline/` (не коммитится)

- [ ] **Step 1: Переложить спеки в gitignored-каталог с именами, которые ждут `Rakefile`/тесты T8**

```bash
mkdir -p examples/real
mv raiffeisen_sbp_payout.yaml   examples/real/raiffeisen.yml
mv adyen_webhooks_v1.yaml       examples/real/adyen_webhooks.yaml
mv apipay_kz_kaspi_openapi.yaml examples/real/apipay_kz.yaml
mv adyen_payout_v68.yaml        examples/real/adyen_payout_v68.yaml
mv adyen_transfers_v4.yaml      examples/real/adyen_transfers_v4.yaml
mv paypal_payouts_v1.json       examples/real/paypal_payouts_v1.json
git status --short   # ожидание: ничего нового не появилось (examples/real/*.{json,yaml,yml} в .gitignore)
```

- [ ] **Step 2: Зафиксировать базовую линию (для сравнения после T8)**

```bash
eval "$(mise env -s zsh)"
mkdir -p tmp/baseline
for f in examples/real/*.yaml examples/real/*.yml examples/real/*.json; do
  n=$(basename "$f"); n=${n%.*}
  bin/forge generate --spec "$f" --out "tmp/baseline/$n" --force > "tmp/baseline/$n.log" 2>&1; echo "$n exit=$?"
done
```
Expected: `adyen_payout_v68`, `paypal_payouts_v1`, `adyen_transfers_v4`, `raiffeisen` → exit 1 со стектрейсом
`NoMethodError`; `adyen_webhooks` → exit 1 `no paths`; `apipay_kz` → exit 3. Это и есть список, который план закрывает.

- [ ] **Step 3: Убедиться, что базовый набор зелёный до начала правок**

Run: `bundle exec rake check`
Expected: rubocop 0 offenses; 216 examples, 0 failures; guard:vendor ok.

Коммита нет (перемещены untracked-файлы).

---

### Task 1: CLI — последний рубеж для не-Forge исключений (exit 70)

**Files:**
- Modify: `lib/forge/cli.rb:57-64`
- Modify: `docs/ARCHITECTURE.md:66-72` (таблица кодов выхода), `CLAUDE.md:87-89`, `REQUIREMENTS.md:450-456`,
  `docs/AUDIT.md` (§ 1.4 коды ошибок), `NOTES.md` (раздел «Решения»)
- Test: `spec/cli_spec.rb`

**Interfaces:**
- Produces: `Forge::CLI::INTERNAL_EXIT = 70`, `Forge::CLI::INTERNAL_HINT` — используются в T8 (тест «no internal error»).

- [ ] **Step 1: Написать падающие тесты**

В `spec/cli_spec.rb` добавить `require 'fileutils'` в начало файла и новый блок в конец `describe 'CLI'`:

```ruby
  describe 'internal errors (not a Forge::Error)' do
    let(:templates) { 'tmp/broken_templates' }

    before do
      FileUtils.mkdir_p(templates)
      File.write("#{templates}/service.rb.erb", "<%= nil.explode %>\n")
    end

    it 'exits 70 with a one-line message, a hint and no stack trace' do
      res = run_cli('generate', '--spec', 'examples/specs/novapay.yaml', '--out', 'tmp/cli_internal', '--force',
                    '--no-verify', '--templates-dir', templates)
      expect(res.exit_code).to eq(Forge::CLI::INTERNAL_EXIT)
      expect(res.stderr).to start_with('error: internal error (NoMethodError): undefined method')
      expect(res.stderr).to include("hint: #{Forge::CLI::INTERNAL_HINT}")
      expect(res.stderr).not_to include('.rb:')
    end

    it 'shows the stack trace under --debug' do
      res = run_cli('generate', '--spec', 'examples/specs/novapay.yaml', '--out', 'tmp/cli_internal', '--force',
                    '--no-verify', '--templates-dir', templates, '--debug')
      expect(res.exit_code).not_to eq(Forge::CLI::INTERNAL_EXIT)
      expect(res.stderr).to include('NoMethodError', '.rb:')
    end
  end
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `bundle exec rspec spec/cli_spec.rb -e 'internal errors'`
Expected: 2 failures — `uninitialized constant Forge::CLI::INTERNAL_EXIT`.

- [ ] **Step 3: Реализация**

В `lib/forge/cli.rb` после `class CLI < Thor` / `exit_on_failure?`:

```ruby
    # sysexits EX_SOFTWARE: необработанное исключение — это баг forge, а не ошибка входа (exit 1–4).
    INTERNAL_EXIT = 70
    INTERNAL_HINT = 'this is a forge bug: rerun with --debug and attach the spec to the report'
```

Заменить `guarded`:

```ruby
    def guarded
      yield
    rescue Forge::Error => e
      raise if options[:debug]

      warn "error: #{e.message}"
      exit e.class.exit_code
    rescue StandardError => e
      raise if options[:debug]

      warn "error: internal error (#{e.class}): #{e.message.lines.first&.strip}\n  hint: #{INTERNAL_HINT}"
      exit INTERNAL_EXIT
    end
```

- [ ] **Step 4: Тесты зелёные**

Run: `bundle exec rspec spec/cli_spec.rb`
Expected: 0 failures.

- [ ] **Step 5: Документация**

`docs/ARCHITECTURE.md` — в таблицу кодов выхода после строки `| 4 |` добавить:
```
| 70 | Внутренняя ошибка forge (необработанное исключение): одна строка `error: internal error (<Class>): …` + hint «rerun with --debug»; это баг генератора, а не ошибка входа |
```
`REQUIREMENTS.md:456` — та же строка после `| 4 |`. `CLAUDE.md:87-89` — дополнить: «Любое другое исключение → `error: internal error …`, exit 70 (`Forge::CLI::INTERNAL_EXIT`); стектрейс только с `--debug`.»
`docs/AUDIT.md` § 1.4 «Коды ошибок» — добавить «70 — internal error».
`NOTES.md` → «Решения», после D-14:
```
### D-15 · Exit 70 для не-Forge исключений
Любое исключение вне иерархии `Forge::Error` печатается одной строкой с hint и завершает процесс кодом 70
(sysexits EX_SOFTWARE). Почему: стектрейс без `--debug` нарушает L-07, а exit 1 маскирует баг под ошибку
входа; отдельный код позволяет `rake real` и CI отличать «спека плохая» от «forge упал».
```

- [ ] **Step 6: Проверка и коммит**

Run: `bundle exec rake check`
```bash
git add lib/forge/cli.rb spec/cli_spec.rb docs/ARCHITECTURE.md REQUIREMENTS.md CLAUDE.md docs/AUDIT.md NOTES.md
git commit -m "cli: map unexpected exceptions to exit 70 with a hint, stack trace only under --debug

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 2: Спека без поля статуса — пустые карты, честные заглушки, рабочий `statuses.field`

**Files:**
- Modify: `lib/forge/analyzers/statuses.rb` (`locate`, `call`), `lib/forge/report_lines.rb:41-49`
- Modify: `lib/forge/renderers/service_view.rb:35-38` (`aligned` → `constant`), `templates/service.rb.erb:17-25, 87-99, 203-211`
- Modify: `lib/forge/renderers/service_spec.rb`, `templates/service_spec.rb.erb:37-52, 78-111`
- Modify: `lib/forge/plan/fixtures.rb:51-58, 97-103`
- Modify: `lib/forge/plan/overrides_edits.rb:7-22`, `lib/forge/plan/overrides_apply.rb:31-33`
- Modify: `templates/integration.md.erb:29-38`
- Modify: `docs/RULES.md` § 3 и § 9, `docs/OUTPUT_FORMAT.md` § 1
- Test: `spec/analyzers/statuses_spec.rb`, `spec/renderers/service_spec.rb`, `spec/renderers/outputs_spec.rb`,
  `spec/plan/overrides_spec.rb`, `spec/report_spec.rb`

**Interfaces:**
- Produces: `Finding(:statuses).value[:field_path]` и `[:response_status_path]` равны `nil`, когда поле не найдено
  (раньше — `['status']`); `Renderers::ServiceView#constant(name, hash, todo)`; `ServiceView#status_path?`;
  `Analyzers::Statuses#call(field_path: nil, id_path: nil)`; `Plan::OverridesEdits.new(overrides, log, spec)`.

- [ ] **Step 1: Тесты анализатора и отчёта**

`spec/analyzers/statuses_spec.rb` — заменить тест `'warns when no status field is found'`:

```ruby
  it 'returns nil paths and warns when no status field is found' do
    finding = statuses_for(spec_with_response('id' => { 'type' => 'string' }))
    expect(finding.value).to include(field_path: nil, response_status_path: nil, map: {}, unmapped: [])
    expect(finding).to have_warning(:status_field_not_found)
  end

  it 'takes a forced field path (statuses.field override) and builds the map from its enum' do
    outcome = { 'type' => 'string', 'enum' => %w[DONE LOST] }
    spec = spec_with_response('id' => { 'type' => 'string' }, 'outcome' => outcome)
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    finding = described_class.new(spec, rules, roles: roles.value).call(field_path: ['outcome'])
    expect(finding.value).to include(field_path: ['outcome'], map: { 'DONE' => 'approved' }, unmapped: ['LOST'])
    expect(finding.confidence).to eq(1.0)
    expect(finding.warnings.map(&:code)).to eq([:unmapped_status])
  end

  it 'raises SpecError for a forced path that does not exist in the response' do
    spec = spec_with_response('id' => { 'type' => 'string' })
    roles = Forge::Analyzers::EndpointRoles.new(spec, rules).call
    expect { described_class.new(spec, rules, roles: roles.value).call(field_path: %w[nope]) }
      .to raise_error(Forge::SpecError, /statuses\.field: no property 'nope'/)
  end
```

`spec/report_spec.rb` — добавить (посмотреть, как в файле строится `findings`; использовать тот же helper):

```ruby
  it 'prints "Statuses: not found" when the analyzer found no status field' do
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                                'operationId' => 'createPayout',
                                'requestBody' => body_json({ 'amount' => { 'type' => 'integer' } }),
                                'responses' => response_json(201, { 'id' => { 'type' => 'string' } })
                              } } }))
    findings = Forge::Analyzers::Runner.run(spec, rules: Forge::Rules.load)
    expect(Forge::Report.text(spec, findings)).to include("\nStatuses: not found\n")
  end
```

- [ ] **Step 2: Тесты падают**

Run: `bundle exec rspec spec/analyzers/statuses_spec.rb spec/report_spec.rb`
Expected: 3–4 failures (`field_path` = `['status']`, `unknown keyword :field_path`, отчёт печатает `Statuses (status): not found`).

- [ ] **Step 3: Анализатор — nil при отсутствии, принудительный путь**

`lib/forge/analyzers/statuses.rb`:

```ruby
      HINT_FIELD = 'statuses.field must name a property of the status (or create) response, e.g. data.state'

      def call(field_path: nil, id_path: nil)
        schema = success_response(role(:status) || role(:create))&.schema
        path, field, confidence = field_path ? forced(schema, field_path) : locate(schema)
        values = field ? enum_or_description(field, path) : []
        map, unmapped = classify(values, path)
        response_id, id_confidence = id_path ? [id_path, 1.0] : response_id(schema)
        value = { field_path: path, map: map, unmapped: unmapped, response_id_path: response_id,
                  response_status_path: path, response_id_confidence: id_confidence }
        finding(:statuses, value, confidence: confidence, source: source_text(path, field, values))
      end
```

`locate` — заменить последнюю строку `[['status'], nil, 0.0]` на `[nil, nil, 0.0]`. Добавить:

```ruby
      # statuses.field из overrides: путь обязан существовать; карта строится из его enum/description.
      def forced(schema, path)
        prop = dig_schema(schema, path)
        return [path, prop, 1.0] if prop

        raise SpecError.new("statuses.field: no property '#{path.join('.')}' in the response schema",
                            pointer: role(:status)&.pointer || role(:create)&.pointer, hint: HINT_FIELD)
      end
```

`enum_or_description(field, path)` вызывает `warn(:status_from_description, ...)` с `path.join('.')` — путь теперь
никогда не nil при наличии field, менять не нужно. `unmapped_warning` тоже.

`lib/forge/report_lines.rb#statuses`:

```ruby
    def statuses
      s = @f[:statuses].value
      return 'Statuses: not found' unless s[:field_path]

      groups = %w[in_progress approved rejected].filter_map do |internal|
        keys = s[:map].select { |_k, v| v == internal }.keys
        "#{keys.join(', ')} → #{internal}" unless keys.empty?
      end
      groups << "unmapped: #{s[:unmapped].join(', ')}" unless s[:unmapped].empty?
      "Statuses (#{s[:field_path].join('.')}): #{groups.join('; ')}"
    end
```

Проверить `lib/forge/report.rb` (JSON): если там `field_path.join` — заменить на `field_path&.join('.')`.

- [ ] **Step 4: Анализатор зелёный, снапшоты не изменились**

Run: `bundle exec rspec spec/analyzers/statuses_spec.rb spec/report_spec.rb spec/cli_spec.rb`
Expected: 0 failures (снапшоты novapay/cardpay/swiftpay байт-в-байт).

- [ ] **Step 5: Тесты рендереров (падающие)**

`spec/renderers/service_spec.rb` — добавить helper и контекст:

```ruby
  # Форма Adyen Payout: ответ без поля статуса, id в pspReference (ещё не в словаре — T5), есть status-эндпоинт.
  def statusless_spec
    id_param = { 'name' => 'id', 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }
    reply = response_json(200, { 'reference' => { 'type' => 'string' } })
    build_spec(security_schemes: { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } }, security: [{ 'b' => [] }],
               paths: {
                 '/payouts' => { 'post' => { 'operationId' => 'createPayout', 'responses' => reply,
                                             'requestBody' => body_json({ 'amount' => { 'type' => 'integer' },
                                                                          'currency' => { 'type' => 'string' } }) } },
                 '/payouts/{id}' => { 'get' => { 'operationId' => 'getPayout', 'parameters' => [id_param],
                                                 'responses' => reply } }
               })
  end

  context 'when the spec has no status field' do
    subject(:code) { render(plan_for_hash(statusless_spec)) }

    it 'renders an empty STATUS_MAP with a TODO and treats a 2xx create as in_progress' do
      expect(code).to include('STATUS_MAP = {}.freeze # TODO(forge): no status field found in the spec',
                              "transition(operation, 'in_progress', provider_status: nil)",
                              "failure(:not_implemented, 'status_field_missing'")
      expect(code).not_to include('apply_status(operation, response.body')
      expect(Forge::Verifier.syntax!([write(plan_for_hash(statusless_spec), 'statusless_service.rb')])).to be_truthy
    end
  end
```

`spec/renderers/outputs_spec.rb` → в `describe Forge::Renderers::ServiceSpec`:

```ruby
    it 'generates a green spec for a plan without status field' do
      dir = generate(plan_for_hash(statusless_spec), 'tmp/out_spec/statusless')
      out = Forge::Verifier.spec!("#{dir}/test_service_spec.rb", load_paths: ['lib', dir])
      expect(out).to include('examples, 0 failures')
      expect(out).to include('1 pending')
    end

    it 'marks the create example pending when the provider status in the example is unmapped' do
      unmapped = response_json(201, { 'id' => { 'type' => 'string' },
                                      'status' => { 'type' => 'string', 'enum' => %w[weird] } },
                               example: { 'id' => 'p1', 'status' => 'weird' })
      spec = build_spec(security_schemes: { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } },
                        security: [{ 'b' => [] }],
                        paths: { '/payouts' => { 'post' => { 'operationId' => 'createPayout', 'responses' => unmapped,
                                                             'requestBody' => body_json({ 'amount' => { 'type' => 'integer' } }) } } })
      dir = generate(plan_for_hash(spec), 'tmp/out_spec/unmapped')
      out = Forge::Verifier.spec!("#{dir}/test_service_spec.rb", load_paths: ['lib', dir])
      expect(out).to include('examples, 0 failures, 1 pending')
    end
```

`statusless_spec` нужен в обоих файлах → вынести в `spec/support/spec_shapes.rb`:

```ruby
# frozen_string_literal: true

# Формы спек, встреченные на реальных API (docs/REAL_SPECS.md), в виде минимальных hash для тестов рендереров.
module SpecShapes
  BEARER = { 'b' => { 'type' => 'http', 'scheme' => 'bearer' } }.freeze
  ID_PARAM = { 'name' => 'id', 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' } }.freeze

  # Ответ без поля статуса, есть status-эндпоинт (Adyen Payout).
  def statusless_spec
    reply = response_json(200, { 'reference' => { 'type' => 'string' } })
    build_spec(security_schemes: BEARER, security: [{ 'b' => [] }], paths: {
                 '/payouts' => { 'post' => { 'operationId' => 'createPayout', 'responses' => reply,
                                             'requestBody' => body_json({ 'amount' => { 'type' => 'integer' },
                                                                          'currency' => { 'type' => 'string' } }) } },
                 '/payouts/{id}' => { 'get' => { 'operationId' => 'getPayout', 'parameters' => [ID_PARAM],
                                                 'responses' => reply } }
               })
  end
end

RSpec.configure { |c| c.include SpecShapes }
```
(в `service_spec.rb` тогда helper не дублировать).

- [ ] **Step 6: Тесты падают**

Run: `bundle exec rspec spec/renderers/service_spec.rb spec/renderers/outputs_spec.rb`
Expected: падение с `NoMethodError: undefined method '+' for nil` в `aligned` (это D1) и красный сгенерированный spec.

- [ ] **Step 7: ServiceView и шаблон сервиса**

`lib/forge/renderers/service_view.rb` — удалить `aligned`, добавить:

```ruby
      # `NAME = { 'k' => 'v', … }.freeze` с выровненными стрелками; пустая карта → `NAME = {}.freeze # TODO(forge): …`.
      def constant(name, hash, todo)
        return ["#{name} = {}.freeze # TODO(forge): #{todo}"] if hash.empty?

        width = hash.keys.map { |k| "'#{k}'".size }.max
        rows = hash.map { |k, v| "  #{"'#{k}'".ljust(width)} => '#{v}'," }
        rows[-1] = rows[-1].delete_suffix(',')
        ["#{name} = {", *rows, '}.freeze']
      end

      def status_path? = !op(:create).response_status_path.nil?
```

`templates/service.rb.erb` строки 17–25 заменить на:

```erb
<% view.constant('STATUS_MAP', plan.status_map, 'no status field found in the spec (statuses.field in overrides.yml)').each do |line| -%>
    <%= line %>
<% end -%>
<% if view.webhook && !plan.event_map.empty? -%>

<% view.constant('EVENT_MAP', plan.event_map, 'no webhook events found').each do |line| -%>
    <%= line %>
<% end -%>
<% end -%>
```

Строки 87–99 (`fetch_status`) заменить на:

```erb
<% if view.op(:status) && view.status_path? -%>
    def fetch_status(operation)
      response = client.get(<%= view.paths.url(:status) %>, headers: auth_headers)
      return failure(http_symbol(response.status), "provider.#{error_code_for(response)}") unless response.status == <%= view.op(:status).success_statuses.first %>

      apply_status(operation, <%= view.paths.body(view.op(:status).response_status_path) %>)
<%= partial('_rescues.erb') -%>
    end
<% elsif view.op(:status) -%>
    def fetch_status(operation)
      response = client.get(<%= view.paths.url(:status) %>, headers: auth_headers)
      return failure(http_symbol(response.status), "provider.#{error_code_for(response)}") unless response.status == <%= view.op(:status).success_statuses.first %>

      # TODO(forge): no status field found in the status response; set statuses.field in overrides.yml
      failure(:not_implemented, 'status_field_missing', body: response.body)
<%= partial('_rescues.erb') -%>
    end
<% else -%>
    def fetch_status(_operation)
      failure(:not_implemented, 'status_endpoint_missing') # TODO(forge): no status endpoint in the spec
    end
<% end -%>
```

Строки 209–210 (`parse_create_response`) заменить на:

```erb
      operations.update(operation.id, provider_operation_id: <%= view.paths.body(view.op(:create).response_id_path) %>)
<% if view.status_path? -%>
      apply_status(operation, <%= view.paths.body(view.op(:create).response_status_path) %>)
<% else -%>
      # TODO(forge): no status field in the create response; a 2xx reply is treated as accepted (in_progress)
      transition(operation, 'in_progress', provider_status: nil)
<% end -%>
```

- [ ] **Step 8: Golden novapay/cardpay/swiftpay байт-в-байт**

Run: `bundle exec rspec spec/renderers/service_spec.rb spec/golden_spec.rb`
Expected: golden зелёные (выравнивание `constant` повторяет прежний `aligned`: `'pending'    => 'in_progress'`).
Если golden отличается — исправлять `constant`, **не** golden.

- [ ] **Step 9: Фикстуры — распознанный статус в синтезированном ответе**

`lib/forge/plan/fixtures.rb`: `synthesize_success` возвращает ключ синтезированного ответа; `create` использует его.

```ruby
      def create
        ep = role(:create)
        fixture = create_request(ep).merge(responses(ep))
        prefer_recognised_status(fixture, synthesize_success(fixture, ep))
        remember_create_success(ep, fixture)
        fixture['expected_operation_status'] = expected_status(success_of(fixture), 'in_progress')
        fixture.compact
      end

      # Успешный ответ без примера: та же схема, что у create → его пример; иначе синтез по схеме. → ключ или nil.
      def synthesize_success(fixture, endpoint, base: nil)
        res = endpoint.responses.find { |r| r.status.start_with?('2') }
        return nil if res&.schema.nil? || fixture.key?("response_#{res.status}")

        key = "response_#{res.status}"
        fixture[key] = Marshal.load(Marshal.dump(success_example(res.schema, base)))
        key
      end

      # Синтезированный ответ: статус — первый распознанный (in_progress), чтобы сгенерированный spec был зелёным.
      def prefer_recognised_status(fixture, key)
        path = @f[:statuses].value[:response_status_path]
        response = key && fixture[key]
        return unless response.is_a?(Hash) && path && !@p[:status_map].key?(dig(response, path).to_s)

        raw = @p[:status_map].find { |_r, internal| internal == 'in_progress' }&.first || @p[:status_map].keys.first
        set_path(response, path, raw) if raw
      end
```
Файл не должен превысить 200 строк (сейчас 177): если превышает — вынести `prefer_recognised_status`
и `synthesize_success` в `lib/forge/plan/fixtures_synthesis.rb` (модуль `Plan::FixturesSynthesis`, `include` в `Fixtures`).

- [ ] **Step 10: Сгенерированный spec — ветки без статуса и `pending` для неотображённого статуса**

`lib/forge/renderers/service_spec.rb` — добавить:

```ruby
      def status_path? = !op(:create).response_status_path.nil?

      # Статус в примере ответа не в карте → сервис вернёт unknown_provider_status; тест честно pending, не красный.
      def unmapped_create_status
        return nil unless status_path?

        raw = dig(fx.dig('create_request', create_response_key), op(:create).response_status_path)
        raw && !plan.status_map.key?(raw.to_s) ? raw : nil
      end
```

`templates/service_spec.rb.erb`, тест `'creates payout (…)'` — первой строкой тела:

```erb
<% if unmapped_create_status -%>
      pending "provider status '<%= unmapped_create_status %>' is not mapped; set statuses.<%= unmapped_create_status %> in overrides.yml"
<% end -%>
```

Блок `#fetch_status` (строки 91–111) заменить на:

```erb
<% if op(:status) && status_response_key && status_path? -%>
  describe '#fetch_status' do
    it 'maps the provider status to <%= fx.dig('fetch_status', 'expected_operation_status') || 'an internal status' %>' do
      operation.provider_operation_id = provider_id
      stub_request(:get, <%= url(:status) %>)
        .to_return(status: <%= op(:status).success_statuses.first %>, body: fixtures.dig('fetch_status', '<%= status_response_key %>').to_json,
                   headers: { 'Content-Type' => 'application/json' })
      result = service.fetch_status(operation)
      expect(result).to be_success
<% if fx.dig('fetch_status', 'expected_operation_status') -%>
      expect(result.data[:status]).to eq('<%= fx.dig('fetch_status', 'expected_operation_status') %>')
<% end -%>
    end
  end
<% elsif op(:status) && status_response_key -%>
  describe '#fetch_status' do
    it 'needs a hand-written status mapping' do
      pending 'no status field in the response (see report.txt: statuses.field)'
      operation.provider_operation_id = provider_id
      stub_request(:get, <%= url(:status) %>)
        .to_return(status: <%= op(:status).success_statuses.first %>, body: fixtures.dig('fetch_status', '<%= status_response_key %>').to_json,
                   headers: { 'Content-Type' => 'application/json' })
      expect(service.fetch_status(operation)).to be_success
    end
  end
<% else -%>
  describe '#fetch_status' do
    it 'is not available in the spec' do
      expect(service.fetch_status(operation).code).to eq('status_endpoint_missing')
    end
  end
<% end -%>
```

`templates/integration.md.erb` после таблицы «Маппинг статусов» (перед `<% unless plan.unmapped_statuses.empty? -%>`):

```erb
<% if plan.status_map.empty? -%>

Поле статуса в ответах не найдено: сервис считает успешный ответ create `in_progress`, `fetch_status` возвращает
`status_field_missing`. Задать вручную: `statuses.field: <путь>` и `statuses.<STATUS>: in_progress|approved|rejected` в `overrides.yml`.
<% end -%>
```

- [ ] **Step 11: Рендереры зелёные**

Run: `bundle exec rspec spec/renderers spec/golden_spec.rb spec/reference_spec.rb`
Expected: 0 failures; golden не изменились.

- [ ] **Step 12: `statuses.field` / `statuses.response_id` в overrides (D9)**

`spec/plan/overrides_spec.rb` — добавить:

```ruby
  it 'relocates the status field with statuses.field and drops status_field_not_found' do
    spec_hash = build_spec(paths: { '/payouts' => { 'post' => {
                             'operationId' => 'createPayout',
                             'requestBody' => body_json({ 'amount' => { 'type' => 'integer' } }),
                             'responses' => response_json(201, { 'ref' => { 'type' => 'string' },
                                                                 'outcome' => { 'type' => 'string', 'enum' => %w[DONE LOST] } })
                           } } })
    spec = ir_for(spec_hash)
    overrides = { 'statuses' => { 'field' => 'outcome', 'response_id' => 'ref', 'LOST' => 'rejected' } }
    findings = Forge::Analyzers::Runner.run(spec, rules: rules, overrides: overrides)
    expect(findings[:statuses].value).to include(field_path: ['outcome'], response_id_path: ['ref'],
                                                 map: { 'DONE' => 'approved', 'LOST' => 'rejected' }, unmapped: [])
    expect(warnings(findings).map(&:code)).not_to include(:status_field_not_found, :response_id_not_found, :unmapped_status)
    expect(applied(findings)).to include('statuses.field → outcome', 'statuses.response_id → ref', 'statuses.LOST → rejected')
  end
```

`lib/forge/plan/overrides_apply.rb:32` → `edits = OverridesEdits.new(@o, self, @spec)`.

`lib/forge/plan/overrides_edits.rb`:

```ruby
      LOCATION_KEYS = %w[field response_id].freeze

      def initialize(overrides, log, spec)
        @o = overrides
        @log = log
        @spec = spec
      end

      def statuses(findings)
        finding = relocated(findings)
        map = finding.value[:map].dup
        @o['statuses'].to_h.except(*LOCATION_KEYS).each do |raw, internal|
          map[raw.to_s] = internal.to_s
          @log.close(:unmapped_status, "'#{raw}'")
          @log.close(:unmapped_event, "status '#{Rules.normalize(raw)}'")
          @log.applied("statuses.#{raw}", internal)
        end
        finding.with(value: finding.value.merge(map: map, unmapped: finding.value[:unmapped] - map.keys))
      end

      private

      # statuses.field / statuses.response_id: анализатор перезапускается с заданными путями — карта строится заново.
      def relocated(findings)
        keys = @o['statuses'].to_h.slice(*LOCATION_KEYS)
        return findings[:statuses] if keys.empty?

        paths = keys.transform_values { |v| v.to_s.split('.') }
        keys.each { |key, value| @log.applied("statuses.#{key}", value) }
        Analyzers::Statuses.new(@spec, rules, findings: findings).call(field_path: paths['field'], id_path: paths['response_id'])
      end
```
(`private` уже есть ниже — переместить `relocated` в приватную секцию, не дублировать `private`.)

Run: `bundle exec rspec spec/plan/overrides_spec.rb` → 0 failures.

- [ ] **Step 13: Документация**

`docs/RULES.md` § 3, после алгоритма: «Не найдено → `field_path: nil`, `STATUS_MAP = {}.freeze` + TODO,
create → `in_progress`, `fetch_status` → `status_field_missing`». § 9 (overrides): описать `statuses.field: <путь>`
и `statuses.response_id: <путь>` — «анализатор перезапускается с этим путём; путь обязан существовать (иначе SpecError)».
`docs/OUTPUT_FORMAT.md` § 1: абзац «Если поле статуса не найдено …» с тремя строками из шаблона выше.
`NOTES.md`: `### D-16 · Нет поля статуса — не падение, а in_progress + TODO` (почему: 2xx на create означает
«принято», это единственный безопасный статус; всё остальное — ручное решение через `statuses.field`).

- [ ] **Step 14: Проверка и коммит**

Run: `bundle exec rake check`
```bash
git add lib/forge/analyzers/statuses.rb lib/forge/report_lines.rb lib/forge/report.rb lib/forge/renderers/service_view.rb \
        lib/forge/renderers/service_spec.rb lib/forge/plan/fixtures.rb lib/forge/plan/fixtures_synthesis.rb \
        lib/forge/plan/overrides_edits.rb lib/forge/plan/overrides_apply.rb templates spec docs/RULES.md docs/OUTPUT_FORMAT.md NOTES.md
git commit -m "renderers, analyzers: survive specs without a status field; statuses.field override

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 3: Payload реквизитов — nil-источники, вложенный контейнер, camelCase, enum типа

**Files:**
- Modify: `lib/forge/renderers/service_payload.rb`
- Modify: `lib/forge/analyzers/field_walker.rb:40-44`, `lib/forge/analyzers/fields.rb:63-68`
- Modify: `docs/RULES.md` § 7, `README.md` «Ограничения»
- Test: `spec/renderers/service_payload_spec.rb` (новый), `spec/analyzers/fields_spec.rb`, `spec/support/spec_shapes.rb`

**Interfaces:**
- Produces: `Forge::Warning(:requisite_type_enum_mismatch)`; `ServicePayload#payload_lines` рендерит вложенный
  контейнер через `tree`.

- [ ] **Step 1: Форма спеки Adyen Transfers в `spec/support/spec_shapes.rb`**

```ruby
  # Контейнер в camelCase, oneOf с discriminator-типом провайдера и полем без источника (Adyen Transfers).
  def discriminated_variants_spec
    variant = lambda do |type, fields|
      { 'type' => 'object', 'required' => ['type'],
        'properties' => { 'type' => { 'type' => 'string', 'enum' => [type] } }.merge(fields) }
    end
    identification = { 'oneOf' => [variant.call('iban', 'iban' => { 'type' => 'string' }, 'address' => { 'type' => 'object' }),
                                   variant.call('usLocal', 'accountNumber' => { 'type' => 'string' })] }
    counterparty = { 'type' => 'object', 'properties' => {
      'balanceAccountId' => { 'type' => 'string' },
      'bankAccount' => { 'type' => 'object', 'properties' => { 'accountIdentification' => identification } }
    } }
    build_spec(security_schemes: BEARER, security: [{ 'b' => [] }], paths: { '/transfers' => { 'post' => {
                 'operationId' => 'createTransfer',
                 'requestBody' => body_json({ 'amount' => { 'type' => 'integer' }, 'currency' => { 'type' => 'string' },
                                              'counterparty' => counterparty }),
                 'responses' => response_json(200, { 'id' => { 'type' => 'string' },
                                                     'status' => { 'type' => 'string', 'enum' => %w[received] } })
               } } })
  end
```

- [ ] **Step 2: Падающие тесты**

`spec/renderers/service_payload_spec.rb`:

```ruby
# frozen_string_literal: true

RSpec.describe Forge::Renderers::ServicePayload do
  def payload_for(hash) = described_class.new(plan_for_hash(hash))

  context 'with a camelCase nested container and a oneOf variant (Adyen Transfers shape)' do
    subject(:payload) { payload_for(discriminated_variants_spec) }

    it 'nests build_recipient at the container path instead of the payload root' do
      # amount — integer без description → major assumed (WARN amount_unit_assumed) → `operation.amount`
      expect(payload.payload_lines).to eq(['amount: operation.amount,', 'currency: operation.currency,',
                                           'counterparty: {', '  balanceAccountId: nil, # TODO(forge): map \'counterparty.balanceAccountId\' (see overrides.yml)',
                                           '  bankAccount: build_recipient(operation, requisite_type)', '}'])
    end

    it 'renders an unmapped variant field as nil with a TODO instead of raising' do
      expect(payload.recipient_lines).to eq(['requisite = operation.payout_requisite.fetch(requisite_type)',
                                             'base = {', '  type: requisite_type,',
                                             "  address: nil, # TODO(forge): map 'counterparty.bankAccount.accountIdentification.address' (see overrides.yml)",
                                             '}.compact', 'case requisite_type',
                                             "when 'bank_account' then base.merge(iban: requisite['iban']).compact",
                                             'else base', 'end'])
    end
  end

  it 'keeps the novapay recipient lines byte-identical to the golden service' do
    golden = File.read('spec/golden/novapay/novapay_service.rb')
    payload_for(Forge::Loader.load('examples/specs/novapay.yaml')).recipient_lines.each do |line|
      expect(golden).to include(line.strip)
    end
  end
end
```
(Последний тест использует `plan_for_hash` с уже загруженным hash: `Loader.load` возвращает Hash с резолвленными
`$ref`, `ir_for` прогонит `RefResolver.resolve` повторно — это идемпотентно.)

`spec/analyzers/fields_spec.rb` — добавить:

```ruby
  it 'recognises a camelCase requisite container and warns when the type enum is not canonical' do
    finding = fields_for(ir_for(discriminated_variants_spec))
    expect(finding.value[:requisite_container]).to eq('counterparty.bankAccount')
    expect(finding.value[:requisite_types]).to eq(['bank_account'])
    # enum виден только у первого варианта oneOf (iban); usLocal — во втором, который walker не обходит (R2)
    expect(finding).to have_warning(:requisite_type_enum_mismatch, message: /enum \(iban\).*\(bank_account\)/,
                                                                    hint: /fields\.counterparty\.bankAccount\.accountIdentification\.type\.source/)
  end
```
(`fields_for` — посмотреть имя helper в начале `fields_spec.rb`; если там другое имя — использовать его.)

- [ ] **Step 3: Тесты падают**

Run: `bundle exec rspec spec/renderers/service_payload_spec.rb spec/analyzers/fields_spec.rb`
Expected: `NoMethodError: undefined method 'gsub' for nil` (D2), контейнер `counterparty.bankAccount.accountIdentification`.

- [ ] **Step 4: Реализация — walker и fields**

`lib/forge/analyzers/field_walker.rb#container?`:

```ruby
      def container?(name, prop, requisite)
        return false unless prop.type == 'object'

        key = Rules.normalize(name)
        @dict['requisite_container'].include?(key) || (requisite && @dict['requisite_types'].include?(key))
      end
```
и в `walk_container`: `type = @dict['requisite_types'].include?(Rules.normalize(path.last)) ? Rules.normalize(path.last) : requisite`.

`lib/forge/analyzers/fields.rb#requisite_types`:

```ruby
      # Типы реквизитов: enum поля типа, если он ⊆ канона (sbp, card, …); иначе — типы, выведенные по полям, + WARN.
      def requisite_types(request)
        canonical = request.filter_map(&:requisite_type).uniq
        type_field = request.find { |m| m.source_expr == 'requisite_type' }
        enum = type_field&.schema&.enum&.map(&:to_s)
        return canonical unless enum
        return enum if (enum - dict['requisite_types']).empty?

        warn_type_enum(type_field.path, enum, canonical)
        canonical.empty? ? enum : canonical
      end

      def warn_type_enum(path, enum, canonical)
        warn(:requisite_type_enum_mismatch,
             "#{path.join('.')} enum (#{enum.join(', ')}) is not the canonical requisite type set " \
             "(#{canonical.join(', ')}); the service sends the canonical type",
             hint: "fields.#{path.join('.')}.source: \"…\"  (overrides.yml) to send the provider's value")
      end
```
Если `fields.rb` превышает 200 строк — вынести `check_external_refs` и связанные методы (`raise_unresolved`,
`check_circular`, `circular`, `external_in_responses`, `unresolved`) в `lib/forge/analyzers/fields_refs.rb`
(модуль `Analyzers::FieldsRefs`, `include`).

- [ ] **Step 5: Реализация — payload**

`lib/forge/renderers/service_payload.rb`:

```ruby
      RECIPIENT_CALL = 'build_recipient(operation, requisite_type)'

      def payload_lines
        outside = @plan.fields[:request].reject { |m| inside_container?(m) }
        tree(container? ? outside + [recipient_mapping] : outside, [])
      end

      # Синтетический лист на пути контейнера: вложенность (counterparty → bankAccount) сохраняется через tree.
      def recipient_mapping
        FieldMapping.new(provider_field: @container.last, path: @container, source_expr: RECIPIENT_CALL, required: true,
                         required_if: nil, transform: nil, schema: nil, confidence: 1.0, requisite_type: nil)
      end

      def variant_lines
        inner = @plan.fields[:request].select { |m| inside_container?(m) }
        base, typed = inner.partition { |m| m.requisite_type.nil? && m.required_if.nil? }
        ['requisite = operation.payout_requisite.fetch(requisite_type)', *base_lines(base)] +
          (typed.empty? ? ['base'] : case_lines(typed.group_by(&:requisite_type)))
      end

      # Все поля отображены → одна строка; есть поле без источника → многострочный hash с TODO и .compact.
      def base_lines(base)
        mapped, todo = base.partition(&:source_expr)
        return ["base = { #{mapped.map { |m| base_entry(m) }.join(', ')} }"] if todo.empty?

        rows = mapped.map { |m| "  #{base_entry(m)}," } +
               todo.map { |m| "  #{m.provider_field}: nil, #{format(TODO, m.path.join('.'))}" }
        ['base = {', *rows, '}.compact']
      end
```
Удалить прежнюю логику `lines[-1] = …` из `payload_lines`. `base_entry`/`variant_line` не меняются (в `typed`
попадают только поля с источником: `requisite_type` выставляется лишь при найденном правиле).

- [ ] **Step 6: Зелёные тесты, golden без изменений**

Run: `bundle exec rspec spec/renderers spec/analyzers/fields_spec.rb spec/golden_spec.rb spec/cli_spec.rb`
Expected: 0 failures. Снапшоты novapay/cardpay/swiftpay без изменений (у них enum типа ⊆ канона или поля типа нет).

- [ ] **Step 7: Документация**

`docs/RULES.md` § 7: «имена контейнеров и типов сравниваются после нормализации (`bankAccount` = `bank_account`)»;
абзац про `requisite_type_enum_mismatch`. `README.md` «Ограничения»: строка «Дискриминатор `oneOf` с собственными
значениями (`iban|usLocal`, Adyen): в payload уходит канонический тип + WARN `requisite_type_enum_mismatch`;
значение провайдера — через `fields.<path>.source`». `NOTES.md` D-17.

- [ ] **Step 8: Проверка и коммит**

Run: `bundle exec rake check`
```bash
git add lib/forge/renderers/service_payload.rb lib/forge/analyzers spec docs/RULES.md README.md NOTES.md
git commit -m "renderers, analyzers: nil-safe variant payloads, nested containers, canonical requisite types

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 4: Path-параметры операций — источники, URL сервиса и spec, фикстуры

**Files:**
- Create: `lib/forge/plan/path_sources.rb`
- Modify: `lib/forge/plan/integration_plan.rb:11-12`, `lib/forge/plan/builder.rb:94-104`, `lib/forge/plan/fixtures.rb:60-65`
- Modify: `lib/forge/analyzers/runner.rb:39-42`, `rules/endpoint_roles.yml:5-7`
- Modify: `lib/forge/renderers/service_paths.rb:15-20`, `lib/forge/renderers/service_spec.rb:34`,
  `lib/forge/renderers/integration_doc.rb:39-43`, `templates/service_spec.rb.erb:14`, `templates/mock_server.rb.erb:133,141`
- Modify: `docs/RULES.md` § 2, `docs/ARCHITECTURE.md` (OperationPlan), `docs/OUTPUT_FORMAT.md` § 1
- Test: `spec/analyzers/endpoint_roles_spec.rb`, `spec/plan/builder_spec.rb`, `spec/analyzers/runner_spec.rb`,
  `spec/renderers/service_spec.rb`, `spec/renderers/outputs_spec.rb`, `spec/support/spec_shapes.rb`

**Interfaces:**
- Produces: `Plan::OperationPlan#path_sources` — `{ 'merchantId' => "credentials.fetch('merchant_id')", 'id' => 'operation.provider_operation_id' }`;
  `Plan::PathSources.for(role, path)`, `.credential_key_of(source) → 'merchant_id' | nil`,
  `.fixture_credentials(operations) → { 'merchant_id' => 'test_merchant_id' }`; INFO `:path_param_credential`.

- [ ] **Step 1: Форма спеки в `spec/support/spec_shapes.rb`**

```ruby
  # Path-параметр аккаунта в create и status (ApiPay/Stripe Connect shape).
  def account_path_spec
    merchant = { 'name' => 'merchantId', 'in' => 'path', 'required' => true, 'schema' => { 'type' => 'string' },
                 'example' => 'm-42' }
    reply = response_json(201, { 'id' => { 'type' => 'string' }, 'status' => { 'type' => 'string', 'enum' => %w[pending paid] } })
    build_spec(security_schemes: BEARER, security: [{ 'b' => [] }], paths: {
                 '/merchants/{merchantId}/payouts' => { 'post' => {
                   'operationId' => 'createPayout', 'parameters' => [merchant], 'responses' => reply,
                   'requestBody' => body_json({ 'amount' => { 'type' => 'integer' }, 'currency' => { 'type' => 'string' } })
                 } },
                 '/merchants/{merchantId}/payouts/{id}' => { 'get' => {
                   'operationId' => 'getPayout', 'parameters' => [merchant, ID_PARAM], 'responses' => reply
                 } }
               })
  end
```

- [ ] **Step 2: Падающие тесты**

`spec/analyzers/endpoint_roles_spec.rb`:

```ruby
  it 'does not take an auth/connection endpoint for create even with "send" in the path (ApiPay shape)' do
    paths = post_op('/connections/{connection}/auth/send-phone', 'connectionAuthSendPhone')
              .merge(post_op('/payouts', 'createPayout'))
    finding = described_class.new(ir_for(build_spec(paths: paths)), rules).call
    expect(finding.value[:create].operation_id).to eq('createPayout')
    expect(finding.value[:other].map(&:operation_id)).to eq(['connectionAuthSendPhone'])
    expect(finding.warnings.map(&:code)).not_to include(:role_conflict)
  end
```

`spec/plan/builder_spec.rb`:

```ruby
  it 'assigns path sources: last status param is the provider id, the rest come from credentials' do
    plan = Forge::Plan::Builder.build(*analyzed(account_path_spec))
    expect(plan.operations[:create].path_sources).to eq('merchantId' => "credentials.fetch('merchant_id')")
    expect(plan.operations[:status].path_sources).to eq('merchantId' => "credentials.fetch('merchant_id')",
                                                         'id' => 'operation.provider_operation_id')
    expect(plan.fixtures.dig('create_request', 'credentials')).to eq('merchant_id' => 'm-42')
  end
```
Helper в начале `spec/plan/builder_spec.rb`:

```ruby
  def analyzed(hash)
    spec = ir_for(hash)
    [spec, Forge::Analyzers::Runner.run(spec, rules: rules)]
  end
```

`spec/analyzers/runner_spec.rb`:

```ruby
  it 'reports credential-sourced path parameters as INFO' do
    findings = described_class.run(ir_for(account_path_spec), rules: rules)
    infos = findings[:endpoint_roles].warnings.select { |w| w.code == :path_param_credential }
    expect(infos.map(&:message)).to eq(['POST /merchants/{merchantId}/payouts: path parameter {merchantId} → credentials.merchant_id',
                                        'GET /merchants/{merchantId}/payouts/{id}: path parameter {merchantId} → credentials.merchant_id'])
    expect(infos.map(&:level).uniq).to eq([:info])
  end
```

`spec/renderers/service_spec.rb`:

```ruby
  it 'interpolates credential path params and the provider id in URLs' do
    code = render(plan_for_hash(account_path_spec))
    expect(code).to include(%q(client.post("#{BASE_URL}/merchants/#{credentials.fetch('merchant_id')}/payouts"),
                            %q(client.get("#{BASE_URL}/merchants/#{credentials.fetch('merchant_id')}/payouts/#{operation.provider_operation_id}"))
  end
```

`spec/renderers/outputs_spec.rb`:

```ruby
    it 'generates a green spec for a plan with path parameters' do
      dir = generate(plan_for_hash(account_path_spec), 'tmp/out_spec/account_path')
      out = Forge::Verifier.spec!("#{dir}/test_service_spec.rb", load_paths: ['lib', dir])
      expect(out).to include('examples, 0 failures')
    end
```

- [ ] **Step 3: Тесты падают**

Run: `bundle exec rspec spec/analyzers/endpoint_roles_spec.rb spec/plan/builder_spec.rb spec/analyzers/runner_spec.rb spec/renderers/service_spec.rb spec/renderers/outputs_spec.rb`
Expected: `send-phone` выбран create (0.85); `NoMethodError path_sources`; URL с `#{operation.provider_operation_id}` в create.

- [ ] **Step 4: Правила ролей**

`rules/endpoint_roles.yml` `negative_words` дополнить: `auth, login, logout, session, sessions, token, tokens,
connection, connections, verify_otp, send_phone`. (`otp` уже есть.) Проверить снапшоты трёх спек после правки —
изменений быть не должно (в их путях этих слов нет).

- [ ] **Step 5: `PathSources` и план**

`lib/forge/plan/path_sources.rb`:

```ruby
# frozen_string_literal: true

module Forge
  module Plan
    # Источники path-параметров: последний параметр status/cancel — id выплаты у провайдера, остальные — credentials.
    module PathSources
      ID_EXPR = 'operation.provider_operation_id'
      ID_ROLES = %i[status cancel].freeze
      CREDENTIAL = /credentials\.fetch\('(\w+)'\)/

      module_function

      # → { 'merchantId' => "credentials.fetch('merchant_id')", 'id' => 'operation.provider_operation_id' }
      def for(role, path)
        names = path.scan(/\{(\w+)\}/).flatten
        id = ID_ROLES.include?(role) ? names.last : nil
        names.to_h { |name| [name, name == id ? ID_EXPR : "credentials.fetch('#{Rules.normalize(name)}')"] }
      end

      def credential_key_of(source) = source[CREDENTIAL, 1]

      # Значения для fixtures.create_request.credentials: example параметра либо test_<key>.
      def fixture_credentials(operations)
        operations.compact.values.flat_map do |op|
          op.path_sources.filter_map do |name, source|
            key = credential_key_of(source)
            key && [key, op.endpoint.parameters.find { |p| p.name == name }&.example || "test_#{key}"]
          end
        end.to_h
      end
    end
  end
end
```

`lib/forge/plan/integration_plan.rb`: добавить `:path_sources` в `OperationPlan` (после `:path_params`).
`lib/forge/plan/builder.rb`: `require_relative 'path_sources'`; в `operation(role, endpoint)` добавить
`path_sources: PathSources.for(role, endpoint.path),`.

`lib/forge/plan/fixtures.rb#create_request`:

```ruby
      def create_request(endpoint)
        body = endpoint.request_body
        request = body&.examples.to_h.values.first || Synth.example(body&.schema, 'request')
        operation, extras = request && FixturesOperation.new(@f).from(request)
        { 'endpoint' => label(endpoint), 'request' => request, 'operation' => operation }.merge(with_path_credentials(extras))
      end

      # credentials из path-параметров всех операций + credentials из примера тела (пример важнее).
      def with_path_credentials(extras)
        path = PathSources.fixture_credentials(@p[:operations])
        return extras.to_h if path.empty?

        extras.to_h.merge('credentials' => path.merge(extras.to_h['credentials'].to_h))
      end
```
(`@p[:operations]` доступен: `Fixtures.new(@spec, @f, parts)` получает `parts` уже с `operations`.)

`lib/forge/analyzers/runner.rb#with_spec_warnings`: `extra = production_default + outside_contract(roles.value) + path_credentials(roles.value) + no_cancel(roles.value)`; добавить:

```ruby
      def path_credentials(value)
        %i[create status cancel balance].flat_map do |role|
          ep = value[role]
          next [] unless ep

          Plan::PathSources.for(role, ep.path).filter_map do |name, source|
            key = Plan::PathSources.credential_key_of(source)
            key && Warning.new(level: :info, code: :path_param_credential, pointer: ep.pointer, hint: 'fill it in credentials',
                               message: "#{ep.method.upcase} #{ep.path}: path parameter {#{name}} → credentials.#{key}")
          end
        end
      end
```
Если `runner.rb` превысит 200 строк — вынести спековые предупреждения (`production_default`, `outside_contract`,
`path_credentials`, `no_cancel`) в `lib/forge/analyzers/spec_warnings.rb` (класс `SpecWarnings.for(spec, roles)`).

- [ ] **Step 6: Рендереры**

`lib/forge/renderers/service_paths.rb`:

```ruby
      def url(role)
        sources = op(role).path_sources
        path = op(role).path.gsub(/\{(\w+)\}/) { "\#{#{sources.fetch(::Regexp.last_match(1))}}" }
        "\"\#{BASE_URL}#{path}\""
      end
```
(удалить `ID_EXPR`).

`lib/forge/renderers/service_spec.rb`:

```ruby
      def url(role)
        sources = op(role).path_sources
        path = op(role).path.gsub(/\{(\w+)\}/) { "\#{#{spec_value(sources.fetch(::Regexp.last_match(1)))}}" }
        "\"\#{described_class::BASE_URL}#{path}\""
      end

      # provider_id — из ответа create; credentials — из fixtures.create_request.credentials (те же значения, что в build_record).
      def spec_value(source)
        key = Plan::PathSources.credential_key_of(source)
        key ? "fixtures.dig('create_request', 'credentials', '#{key}')" : 'provider_id'
      end
```
(удалить `ID_EXPR`). `templates/service_spec.rb.erb:14` → `  let(:create_url) { <%= url(:create) %> }`.

`lib/forge/renderers/integration_doc.rb#credential_keys` — добавить в конец выражения:
`+ plan.operations.compact.values.flat_map { |op| op.path_sources.values.filter_map { |s| Plan::PathSources.credential_key_of(s) } }`
и завершить `.uniq`.

`templates/mock_server.rb.erb:133` и `:141`: `path_params.first` → `path_params.last` (id — последний параметр).

- [ ] **Step 7: Зелёные тесты, golden без изменений**

Run: `bundle exec rspec spec/analyzers spec/plan spec/renderers spec/golden_spec.rb spec/cli_spec.rb`
Expected: 0 failures. Для novapay `url(:status)` даёт прежнюю строку `#{operation.provider_operation_id}`;
`create_url` в golden spec — прежняя `"#{described_class::BASE_URL}/payouts"`.

- [ ] **Step 8: Документация**

`docs/RULES.md` § 2: новые `negative_words`. `docs/ARCHITECTURE.md`: в описании `OperationPlan` добавить
`path_sources`. `docs/OUTPUT_FORMAT.md` § 1: «path-параметры: `{id}` последний в status/cancel →
`operation.provider_operation_id`; остальные → `credentials.fetch('<snake_name>')` + INFO `path_param_credential`».
`NOTES.md` D-18.

- [ ] **Step 9: Проверка и коммит**

Run: `bundle exec rake check`
```bash
git add lib rules templates spec docs NOTES.md
git commit -m "plan, renderers: path parameter sources (provider id vs credentials), auth words are negative for create

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 5: Поиск статуса и id — общий обход схемы, нормализация, вложенный объект статуса

**Files:**
- Create: `lib/forge/analyzers/schema_search.rb`
- Modify: `lib/forge/analyzers/statuses.rb` (`find_property`, `candidates`, `response_id`, `ID_TESTS`),
  `lib/forge/analyzers/webhooks.rb:124-142`, `rules/status_map.yml:10-12`
- Modify: `docs/RULES.md` § 3
- Test: `spec/analyzers/statuses_spec.rb`, `spec/analyzers/webhooks_spec.rb`, `spec/rules/rules_spec.rb`

**Interfaces:**
- Produces: `Analyzers::SchemaSearch.candidates(schema, wrappers, max_depth: 3) → [[path, Schema], …]`
  (порядок: длина пути → wrapper-ветки раньше прочих → порядок в схеме; путь ≤ 3 сегментов).

- [ ] **Step 1: Падающие тесты**

`spec/analyzers/statuses_spec.rb`:

```ruby
  it 'finds a nested status object (status.value) — Raiffeisen shape' do
    status = { 'type' => 'object', 'properties' => { 'value' => { 'type' => 'string', 'enum' => %w[COMPLETED DECLINED IN_PROGRESS] },
                                                     'date' => { 'type' => 'string' } } }
    finding = statuses_for(spec_with_response('id' => { 'type' => 'string' }, 'status' => status))
    expect(finding.value).to include(field_path: %w[status value], response_id_path: ['id'], unmapped: [])
    expect(finding.value[:map]).to eq('COMPLETED' => 'approved', 'DECLINED' => 'rejected', 'IN_PROGRESS' => 'in_progress')
  end

  it 'finds batch_status two levels down and a *_id field — PayPal shape' do
    header = { 'type' => 'object', 'properties' => { 'payout_batch_id' => { 'type' => 'string' },
                                                     'batch_status' => { 'type' => 'string', 'enum' => %w[PENDING SUCCESS DENIED] } } }
    finding = statuses_for(spec_with_response('batch_header' => header))
    expect(finding.value).to include(field_path: %w[batch_header batch_status],
                                     response_id_path: %w[batch_header payout_batch_id], response_id_confidence: 0.7)
    expect(finding.value[:map]).to eq('PENDING' => 'in_progress', 'SUCCESS' => 'approved', 'DENIED' => 'rejected')
  end

  it 'matches camelCase names against the dictionary — Adyen shape (resultCode, pspReference)' do
    result = { 'type' => 'string', 'enum' => %w[Received Authorised Refused] }
    finding = statuses_for(spec_with_response('pspReference' => { 'type' => 'string' }, 'resultCode' => result))
    expect(finding.value).to include(field_path: ['resultCode'], response_id_path: ['pspReference'], response_id_confidence: 0.85)
    expect(finding.value[:map]).to eq('Received' => 'in_progress', 'Authorised' => 'in_progress', 'Refused' => 'rejected')
  end

  it 'prefers the root status over a status nested in a non-wrapper object' do
    nested = { 'type' => 'object', 'properties' => { 'status' => { 'type' => 'string', 'enum' => %w[active] } } }
    finding = statuses_for(spec_with_response('status' => { 'type' => 'string', 'enum' => %w[pending] }, 'recipient' => nested))
    expect(finding.value[:field_path]).to eq(['status'])
  end
```

`spec/rules/rules_spec.rb`:

```ruby
  it 'status dictionary has value fields for status objects and psp_reference as an id' do
    dict = rules.fetch(:status_map)
    expect(dict['status_value_fields']).to eq(%w[value code name status state])
    expect(dict['status_fields']).to include('result_code')
    expect(dict['id_fields']).to include('psp_reference')
  end
```

- [ ] **Step 2: Тесты падают**

Run: `bundle exec rspec spec/analyzers/statuses_spec.rb spec/rules/rules_spec.rb`
Expected: 5 failures (`field_path: nil` в трёх формах, словарь без ключей).

- [ ] **Step 3: Словарь**

`rules/status_map.yml` строки 10–12:

```yaml
status_fields: [status, state, payout_status, transfer_status, payment_status, transaction_status, result, batch_status,
                result_code, status_code, payout_state, transfer_state]
# Объект статуса ({status: {value: COMPLETED, date: …}}): enum ищется в этих полях объекта с именем из status_fields.
status_value_fields: [value, code, name, status, state]
id_fields:     [id, payout_id, transfer_id, payment_id, transaction_id, reference_id, uuid, code, psp_reference]
wrappers:      [data, result, payout, transfer, payment, response, transaction]
```
(имена — snake_case; сравнение после `Rules.normalize`, поэтому `resultCode`, `pspReference`, `batch_status` совпадают.)

- [ ] **Step 4: `SchemaSearch`**

`lib/forge/analyzers/schema_search.rb`:

```ruby
# frozen_string_literal: true

module Forge
  module Analyzers
    # Обход свойств схемы ответа для поиска полей по имени: корень → внутри wrappers → любые объекты.
    # max_depth — максимальная длина пути (3 = `data.payout.status`, как у прежнего обхода wrappers).
    module SchemaSearch
      module_function

      # → [[path, Schema], …]: сначала мельче, среди равных — ветки wrappers (data, payout…) раньше прочих, затем порядок схемы.
      def candidates(schema, wrappers, max_depth: 3)
        collect(schema, wrappers, [], 0, max_depth)
          .sort_by.with_index { |(path, _prop, rank), index| [path.size, rank, index] }
          .map { |path, prop, _rank| [path, prop] }
      end

      # rank: 0 — все предки в wrappers, 1 — есть предок вне списка.
      def collect(schema, wrappers, prefix, rank, max_depth)
        return [] unless schema&.properties

        schema.properties.flat_map do |name, prop|
          path = prefix + [name]
          child_rank = wrappers.include?(Rules.normalize(name)) ? rank : 1
          own = [[path, prop, rank]]
          path.size < max_depth ? own + collect(prop, wrappers, path, child_rank, max_depth) : own
        end
      end
    end
  end
end
```

- [ ] **Step 5: `Statuses` и `Webhooks` через `SchemaSearch`**

`lib/forge/analyzers/statuses.rb`: `require_relative 'schema_search'`; заменить `find_property`, `candidates`, `ID_TESTS`, `response_id`:

```ruby
      ID_TESTS = [[->(p, _d) { p == ['id'] }, 0.95],
                  [->(p, d) { p.size == 1 && d.include?(Rules.normalize(p.first)) }, 0.85],
                  [->(p, d) { p.size > 1 && d.include?(Rules.normalize(p.last)) }, 0.8],
                  [->(p, _d) { Rules.normalize(p.last).end_with?('_id') }, 0.7]].freeze

      def find_property(schema, require:)
        candidates(schema).each do |path, prop|
          next unless status_name?(path)
          return [path, prop, 0.95] if require == :enum && prop.enum
          return [path, prop, 0.6] if require == :description && prop.description.to_s.match?(QUOTED)
        end
        nil
      end

      # `status`, `data.state`, `resultCode`, `status.value` (объект статуса с полем value/code) — после нормализации.
      def status_name?(path)
        last, parent = path.last(2).reverse.map { |p| Rules.normalize(p) }
        return true if dict['status_fields'].include?(last)

        parent && dict['status_fields'].include?(parent) && dict['status_value_fields'].include?(last)
      end

      def candidates(schema) = SchemaSearch.candidates(schema, dict['wrappers'])
```
`locate` вызывает `find_property(schema, require: :enum) || find_property(schema, require: :description)` (без `dict['status_fields']`).
`response_id` без изменений по структуре (использует `candidates` и `ID_TESTS`).

`lib/forge/analyzers/webhooks.rb`: удалить собственный `candidates`, `require_relative 'schema_search'`,
`field_path` использовать `SchemaSearch.candidates(schema, status_dict['wrappers'])` и сравнивать
`names.include?(Rules.normalize(path.last))`.

- [ ] **Step 6: Зелёные тесты, снапшоты и golden без изменений**

Run: `bundle exec rspec spec/analyzers spec/renderers spec/golden_spec.rb spec/cli_spec.rb`
Expected: 0 failures (у novapay/swiftpay статус в корне, у cardpay — в wrapper `data`: порядок кандидатов их не меняет).

- [ ] **Step 7: Документация и коммит**

`docs/RULES.md` § 3: обновить YAML-блок и алгоритм («имена сравниваются после нормализации; объект статуса
`status.value`; поиск: корень → wrappers → любые объекты, путь ≤ 3 сегментов; id: `*_id` в любом месте → 0.7»).

Run: `bundle exec rake check`
```bash
git add lib/forge/analyzers rules/status_map.yml spec docs/RULES.md
git commit -m "analyzers: shared schema search, normalized names, nested status objects and *_id fields

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 6: Auth — порядок предпочтения схем и вывод из header-параметра

**Files:**
- Create: `rules/auth.yml`
- Modify: `lib/forge/analyzers/auth.rb`, `lib/forge/report_lines.rb:33-39`
- Modify: `docs/RULES.md` (новый § 11), `REQUIREMENTS.md:404` (A-05: список словарей), `docs/ARCHITECTURE.md` (Rules)
- Test: `spec/analyzers/auth_spec.rb`, `spec/rules/rules_spec.rb`

**Interfaces:**
- Produces: INFO `:auth_alternative` (поддерживаемая, но не выбранная схема) вместо UNSUPPORTED `:<type>_alternative`
  для apiKey/http; WARN `:auth_from_header_param`; `Finding(:auth).value[:scheme_name]` может быть nil.

- [ ] **Step 1: Падающие тесты**

`spec/analyzers/auth_spec.rb`:

```ruby
  it 'prefers a header api key over basic and query keys; other supported schemes are INFO' do
    schemes = { 'q' => { 'type' => 'apiKey', 'in' => 'query', 'name' => 'clientKey' },
                'b' => { 'type' => 'http', 'scheme' => 'basic' },
                'h' => { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' } }
    finding = auth_for(spec_with(schemes, [{ 'q' => [] }, { 'b' => [] }, { 'h' => [] }]))
    expect(finding.value).to include(type: 'api_key', header: 'X-API-Key', scheme_name: 'h')
    expect(finding.warnings.map { |w| [w.level, w.code] }).to eq([[:info, :auth_alternative], [:info, :auth_alternative]])
    expect(finding.warnings.first.message).to include("'q' (api_key_query) is also accepted; 'h' (api_key_header) is used")
  end

  it 'still reports oauth2 alternatives as UNSUPPORTED when a supported scheme wins' do
    schemes = { 'o' => { 'type' => 'oauth2', 'flows' => {} }, 'b' => { 'type' => 'http', 'scheme' => 'basic' } }
    finding = auth_for(spec_with(schemes, [{ 'o' => [] }, { 'b' => [] }]))
    expect(finding.value[:type]).to eq('basic')
    expect(finding).to have_warning(:oauth2_alternative, level: :unsupported)
  end

  it 'infers bearer from an Authorization header parameter when there are no security schemes (Raiffeisen)' do
    header = { 'name' => 'Authorization:', 'in' => 'header', 'required' => true, 'schema' => { 'type' => 'string' },
               'description' => 'Bearer secretKey' }
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                                'operationId' => 'createPayout', 'parameters' => [header],
                                'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
                                'responses' => { '200' => { 'description' => 'ok' } }
                              } } }))
    finding = auth_for(spec)
    expect(finding.value).to include(type: 'bearer', header: 'Authorization', credential_key: 'token', scheme_name: nil)
    expect(finding.confidence).to eq(0.6)
    expect(finding).to have_warning(:auth_from_header_param, level: :warn, hint: /auth\.type/)
    expect(finding).not_to have_warning(:auth_not_found)
  end

  it 'infers an api key from an X-Api-Key header parameter' do
    header = { 'name' => 'X-Api-Key', 'in' => 'header', 'required' => true, 'schema' => { 'type' => 'string' } }
    spec = ir_for(build_spec(paths: { '/payouts' => { 'post' => {
                                'operationId' => 'createPayout', 'parameters' => [header],
                                'requestBody' => body_json({ 'a' => { 'type' => 'integer' } }),
                                'responses' => { '200' => { 'description' => 'ok' } }
                              } } }))
    expect(auth_for(spec).value).to include(type: 'api_key', header: 'X-Api-Key', location: 'header')
  end
```

`spec/rules/rules_spec.rb`:

```ruby
  it 'loads the auth preference dictionary' do
    expect(rules.fetch(:auth)['preference']).to eq(%w[api_key_header bearer basic api_key_query api_key_cookie])
    expect(rules.fetch(:auth).dig('header_params', 'bearer')).to eq(['authorization'])
  end
```

- [ ] **Step 2: Тесты падают**

Run: `bundle exec rspec spec/analyzers/auth_spec.rb spec/rules/rules_spec.rb`
Expected: 5 failures.

- [ ] **Step 3: Словарь**

`rules/auth.yml`:

```yaml
# Выбор схемы авторизации (docs/RULES.md § 11).
# preference — порядок при нескольких альтернативах в `security` (первая поддерживаемая по этому списку побеждает).
preference: [api_key_header, bearer, basic, api_key_query, api_key_cookie]
# Без securitySchemes: header-параметр create-эндпоинта с таким именем (после нормализации, без завершающего «:»).
header_params:
  bearer:  [authorization]
  api_key: [x_api_key, api_key, apikey, x_auth_token, x_token, x_access_token, api_token, x_api_token, x_secret_key, secret_key]
```

- [ ] **Step 4: Анализатор**

`lib/forge/analyzers/auth.rb` — заменить `call`, `unsupported_alternative`, `fallback`, добавить методы:

```ruby
      def call
        alternatives = requirements.map { |req| scheme_for(req.keys.first) }.compact
        supported, unsupported = alternatives.partition { |s| supported?(s) }
        unsupported.each { |s| unsupported_alternative(s) }
        chosen = supported.min_by { |s| rank(s) }
        return fallback(unsupported) unless chosen

        (supported - [chosen]).each { |s| ignored_alternative(s, chosen) }
        finding(:auth, describe(chosen), confidence: 0.95, source: "securitySchemes.#{chosen.name} (#{chosen.type})")
      end

      private

      def auth_dict = rules.fetch(:auth)

      # api_key_header | api_key_query | api_key_cookie | bearer | basic
      def kind(scheme) = scheme.type == 'apiKey' ? "api_key_#{scheme.location}" : scheme.scheme.to_s
      def rank(scheme) = auth_dict['preference'].index(kind(scheme)) || auth_dict['preference'].size

      def ignored_alternative(scheme, chosen)
        info(:auth_alternative, "security scheme '#{scheme.name}' (#{kind(scheme)}) is also accepted; " \
                                "'#{chosen.name}' (#{kind(chosen)}) is used",
             pointer: pointer(scheme), hint: 'auth.type: api_key|bearer|basic  (overrides.yml) to switch')
      end

      def fallback(unsupported)
        return bearer_fallback(unsupported.first) if unsupported.first

        from_header_param || none
      end

      def none
        warn(:auth_not_found, 'no security requirement on the create endpoint or at the root',
             pointer: '#/security', hint: 'auth.type: api_key|bearer|basic (overrides.yml)')
        finding(:auth, NONE, confidence: 0.0, source: 'no security found')
      end

      # Без securitySchemes: header-параметр `Authorization` → bearer; `X-Api-Key`-подобный → api_key. 0.6 + WARN.
      def from_header_param
        create = role(:create)
        param = create&.parameters&.find { |p| p.location == 'header' && header_kind(p) }
        return nil unless param

        kind = header_kind(param)
        warn(:auth_from_header_param, "no securitySchemes; header parameter '#{param.name}' on #{create.path} looks like #{kind} auth",
             pointer: create.pointer, hint: 'auth.type: api_key|bearer|basic (overrides.yml) to confirm or change')
        finding(:auth, header_param_value(kind, param), confidence: 0.6, source: "header parameter #{param.name}")
      end

      def header_kind(param)
        name = Rules.normalize(header_name(param))
        auth_dict['header_params'].find { |_kind, names| names.include?(name) }&.first
      end

      def header_name(param) = param.name.strip.delete_suffix(':')

      def header_param_value(kind, param)
        return BEARER.merge(scheme_name: nil) if kind == 'bearer'

        { type: 'api_key', scheme_name: nil, header: header_name(param), prefix: nil, credential_key: 'api_key',
          credential_keys: ['api_key'], location: 'header', param_name: header_name(param) }
      end
```
`unsupported_alternative` оставить только для неподдерживаемых типов (`oauth2`, `openIdConnect`, `mutualTLS`) —
код и текст без изменений. Если файл превышает 200 строк — вынести `from_header_param`, `header_kind`,
`header_name`, `header_param_value` в `lib/forge/analyzers/auth_header_param.rb` (модуль, `include`).

`lib/forge/report_lines.rb#auth`: `"Auth: #{a[:scheme_name] || 'header parameter'} (#{a[:type]}, #{where}) → …"`.

- [ ] **Step 5: Зелёные тесты, снапшоты без изменений**

Run: `bundle exec rspec spec/analyzers spec/cli_spec.rb spec/golden_spec.rb spec/report_spec.rb`
Expected: 0 failures. Novapay — единственная схема; cardpay — bearer; swiftpay — basic + oauth2 (UNSUPPORTED сохраняется).

- [ ] **Step 6: Документация и коммит**

`docs/RULES.md` — добавить `## 11. \`auth.yml\` — выбор схемы авторизации` с YAML и правилами (предпочтение,
вывод из header-параметра, confidence 0.6 + WARN). `REQUIREMENTS.md:404` A-05: добавить `auth` в список словарей.
`docs/ARCHITECTURE.md`: в описании Rules добавить `auth.yml`. `NOTES.md` D-19: «порядок предпочтения auth — header
apiKey > bearer > basic > query: заголовок не попадает в логи/URL и не требует Base64 пары».

Run: `bundle exec rake check`
```bash
git add rules/auth.yml lib/forge/analyzers lib/forge/report_lines.rb spec docs REQUIREMENTS.md NOTES.md
git commit -m "analyzers: auth preference order, header-parameter fallback, rules/auth.yml

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 7: IR — `x-webhooks`; loader — hint для документа только с webhooks

**Files:**
- Modify: `lib/forge/ir/builder.rb:56-60`, `lib/forge/loader.rb:54-64`
- Create: `spec/fixtures/broken/webhooks_only.yaml`
- Modify: `docs/ARCHITECTURE.md` (Load/IR), `docs/TEST_SPECS.md` § 4, `REQUIREMENTS.md:400-401` (A-01/A-02)
- Test: `spec/ir/builder_spec.rb`, `spec/loader_spec.rb`

- [ ] **Step 1: Фикстура и падающие тесты**

`spec/fixtures/broken/webhooks_only.yaml`:

```yaml
openapi: 3.1.0
info: { title: Webhooks only, version: '1' }
webhooks:
  PAYOUT_COMPLETED:
    post:
      operationId: payoutCompleted
      requestBody:
        content:
          application/json:
            schema: { type: object, properties: { status: { type: string } } }
      responses:
        '200': { description: ok }
```

`spec/loader_spec.rb` — в таблицу битых файлов добавить `'webhooks_only.yaml' => 'no paths'` и отдельный тест:

```ruby
  it 'explains that a webhooks-only document cannot produce a service' do
    expect { described_class.load('spec/fixtures/broken/webhooks_only.yaml') }
      .to raise_error(Forge::SpecError, /declares only webhooks.*pass the provider API spec/m)
  end
```

`spec/ir/builder_spec.rb`:

```ruby
  it 'reads Redocly x-webhooks as top-level webhooks' do
    hash = build_spec(paths: { '/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                            'responses' => { '200' => { 'description' => 'ok' } } } } })
    hash['x-webhooks'] = { 'newPay' => { 'post' => { 'operationId' => 'callbackTransaction',
                                                     'responses' => { '200' => { 'description' => 'ok' } } } } }
    spec = described_class.build(hash)
    expect(spec.webhooks.map(&:operation_id)).to eq(['callbackTransaction'])
    expect(spec.webhooks.first).to have_attributes(source: :webhooks, path: 'newPay', pointer: '#/x-webhooks/newPay/post')
  end
```

- [ ] **Step 2: Тесты падают** — `bundle exec rspec spec/loader_spec.rb spec/ir/builder_spec.rb`.

- [ ] **Step 3: Реализация**

`lib/forge/ir/builder.rb`:

```ruby
      WEBHOOK_KEYS = %w[webhooks x-webhooks].freeze # OpenAPI 3.1 и расширение Redocly для 3.0

      def webhooks
        WEBHOOK_KEYS.flat_map do |key|
          @hash[key].to_h.flat_map { |name, item| operations(item, "#/#{key}/#{escape(name)}", name, :webhooks) }
        end
      end
```

`lib/forge/loader.rb#validate`:

```ruby
      paths = spec['paths']
      return if paths.is_a?(Hash) && !paths.empty?

      raise error('no paths', no_paths_hint(spec), '#/paths')
    end

    def no_paths_hint(spec)
      webhooks_only = %w[webhooks x-webhooks].any? { |k| spec[k].is_a?(Hash) && !spec[k].empty? }
      return 'the document must declare at least one path' unless webhooks_only

      'the document declares only webhooks; pass the provider API spec (the one with `paths`) — ' \
        'webhooks alone cannot produce a payout service'
    end
```

- [ ] **Step 4: Зелёные тесты** — `bundle exec rspec spec/loader_spec.rb spec/ir/builder_spec.rb spec/cli_spec.rb`
(цикл `broken` в `cli_spec` автоматически проверит `webhooks_only.yaml`: exit 1, `error:`, `hint:`).

- [ ] **Step 5: Документация и коммит**

`docs/ARCHITECTURE.md` Load/IR: «`webhooks` и `x-webhooks`». `docs/TEST_SPECS.md` § 4: строка `webhooks_only.yaml`.
`REQUIREMENTS.md:400` A-01: «нет `paths` (в т. ч. документ только с `webhooks`) → SpecError с подсказкой»; A-02: `x-webhooks`.

Run: `bundle exec rake check`
```bash
git add lib/forge/ir/builder.rb lib/forge/loader.rb spec docs REQUIREMENTS.md
git commit -m "ir, loader: x-webhooks support and a clear hint for webhooks-only documents

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 8: Реальные спеки — `generate` в контуре, новый корпус, CI

**Files:**
- Modify: `Rakefile:27-45, 166-201`, `spec/real_specs_spec.rb`, `.github/workflows/ci.yml` (job `real-specs`)
- Modify: `docs/REAL_SPECS.md`, `NOTES.md` («Реальные спеки»), `README.md:225-241`, `docs/TESTING.md` § 9

**Interfaces:**
- Produces: `rake real:generate`; `rake real` = fetch → analyze → generate → spec; `examples/real/reports/SUMMARY.md`
  получает колонку «generate».

- [ ] **Step 1: Rakefile — корпус и `real:generate`**

`REAL_SPECS` дополнить:

```ruby
  'raiffeisen' => 'https://raw.githubusercontent.com/Raiffeisen-DGTL/ecom-API/master/payout.yml',
  'adyen_webhooks' => 'https://raw.githubusercontent.com/Adyen/adyen-openapi/main/yaml/Webhooks-v1.yaml'
```
Добавить рядом:

```ruby
# Допустимые коды `generate`: корпус — только 0, кроме square (нет create → 2) и adyen_webhooks (нет paths → 1);
# локальные файлы вне корпуса — 0/2/3 (главное — никогда не 70 и не стектрейс). Расширять список — только с записью в NOTES.md.
REAL_GENERATE_EXIT = { 'square' => [2], 'adyen_webhooks' => [1] }.freeze
LOCAL_GENERATE_EXIT = [0, 2, 3].freeze
```

В `namespace :real` добавить:

```ruby
  desc 'bin/forge generate для каждой спеки в examples/real/ (в т. ч. локальных, не из REAL_SPECS) → tmp/real/<name>'
  task :generate do
    files = Dir['examples/real/*.{json,yaml,yml}'].sort
    rows = files.map do |file|
      name = File.basename(file, '.*')
      flags = REAL_FLAGS.fetch(name, [])
      out, status = Open3.capture2e('bin/forge', 'generate', '--spec', file, '--out', "tmp/real/#{name}", '--force', *flags)
      allowed = REAL_GENERATE_EXIT.fetch(name) { REAL_SPECS.key?(name) ? [0] : LOCAL_GENERATE_EXIT }
      ok = allowed.include?(status.exitstatus) && !out.include?('internal error')
      abort "#{name}: exit #{status.exitstatus} (allowed #{allowed})\n#{out.lines.last(15).join}" unless ok
      "| #{name} | #{flags.join(' ')} | exit #{status.exitstatus} | #{out[/Done: .*/] || out[/error: .*/]} |"
    end
    File.write('examples/real/reports/GENERATE.md',
               "# Реальные спеки — `rake real:generate`\n\n| Спека | Флаги | Код | Итог |\n|---|---|---|---|\n#{rows.join("\n")}\n")
    puts rows
  end
```
`task real: %w[real:fetch real:analyze real:generate real:spec]`.

- [ ] **Step 2: `spec/real_specs_spec.rb` — новые кейсы и проверка `generate`**

В `CASES` добавить:

```ruby
    'raiffeisen' => { flags: [], exit: 0, roles: { create: 'post-payout-v1-payouts', status: 'get-payout-v1-payouts-id' },
                      auth: 'bearer', warns: %w[auth_from_header_param signature_not_found] },
    'adyen_webhooks' => { flags: [], exit: 1, stderr: /declares only webhooks/ }
```
Изменить ожидания: `'adyen_payout'` → `auth: 'api_key'`, `warns: %w[no_webhook]` (статус теперь найден в `resultCode`);
`'paypal_payouts'` → `warns: %w[array_field_unsupported amount_field_not_found]`.

Тест `'analyzes with the expected exit code, roles and auth'` — первой строкой после `res = …`:

```ruby
        if expected[:exit] != 0
          expect(res.exit_code).to eq(expected[:exit])
          expect(res.stderr).to match(expected[:stderr])
          next
        end
```
(`next` внутри `it` не работает — оформить как `return` из helper-метода `check_analyze(res, expected)` либо
разделить на два `it` по условию `expected[:exit].zero?`.)

Добавить в цикл `CASES`:

```ruby
      it 'generates without an internal error' do
        res = Timeout.timeout(180) do
          run_cli('generate', '--spec', spec_file(name), '--out', "tmp/real/#{name}", '--force', *expected[:flags])
        end
        expect(res.exit_code).to eq(expected.fetch(:generate_exit, expected[:exit])), res.stderr
        expect(res.stderr).not_to include('internal error', '.rb:')
      end
```
и `generate_exit: 2` в кейс `square`.

Добавить в конец describe — локальные спеки вне корпуса (apipay_kz и YAML-дубликаты Adyen/PayPal):

```ruby
  describe 'local specs outside the corpus' do
    known = CASES.keys
    Dir['examples/real/*.{json,yaml,yml}'].reject { |f| known.include?(File.basename(f, '.*')) }.sort.each do |file|
      it "never crashes on #{File.basename(file)}" do
        res = Timeout.timeout(180) { run_cli('generate', '--spec', file, '--out', "tmp/real/#{File.basename(file, '.*')}", '--force') }
        expect([0, 2, 3]).to include(res.exit_code), res.stderr
        expect(res.stderr).not_to include('internal error', '.rb:')
      end
    end
  end
```

- [ ] **Step 3: Прогон корпуса**

```bash
eval "$(mise env -s zsh)"
bundle exec rake real:fetch          # скачает raiffeisen.yml (уже лежит — skip) и adyen_webhooks.yaml (уже лежит — skip)
REAL_UPDATE=1 bundle exec rake real:spec   # обновить снапшоты analyze (auth/статусы изменились в T5–T6) — просмотреть diff examples/real/reports/
bundle exec rake real:generate
```
Expected: `real:generate` завершается без `abort`; `GENERATE.md` содержит строки для 12 файлов; ни одной
строки с `internal error`. Для каждой спеки записать фактический код в `docs/REAL_SPECS.md` § 2 (таблица «Ожидание»):

| Спека | Ожидаемый `generate` |
|---|---|
| adyen_payout, adyen_payout_v68 | 0 (статусы из `resultCode`, auth apiKey header) |
| adyen_transfers, adyen_transfers_v4 | 0 или 3; при 3 — хвост rspec в `GENERATE.md` и карточка в «Остаток» с причиной |
| paypal_payouts, paypal_payouts_v1 | 0 (статусы из `batch_header.batch_status`; сумма внутри `items[]` — WARN, R7) |
| raiffeisen | 0 (auth из header-параметра, webhook из `x-webhooks`) |
| apipay_kz | 0 или 3 (не payout-API: create с WARN `low_confidence`) |
| stripe, paystack, plaid | 0 или 3 |
| square | 2 |
| adyen_webhooks | 1 |

Если какая-то спека даёт exit 3: **не понижать планку** и не менять ожидание молча — добавить строку в
`NOTES.md` «Реальные спеки» (что именно красное, какой WARN это объясняет) и карточку в `docs/AGENT_TASKS.md` → «Остаток».
Если exit 70 или стектрейс — это дефект, чинится в рамках этой задачи по тому же циклу (тест → код) прежде, чем идти дальше.

- [ ] **Step 4: CI и документация**

`.github/workflows/ci.yml` job `real-specs`: шаг `run: bundle exec rake real` (уже так, если нет — добавить);
`continue-on-error: true` сохранить (сеть). Добавить `- uses: actions/upload-artifact@v4` с `examples/real/reports/`.

`docs/REAL_SPECS.md` § 1: строки 8 (Raiffeisen SBP Payout, YAML 3.0.0, bearer через header-параметр, `x-webhooks`)
и 9 (Adyen Webhooks v1 — документ без `paths`, ожидание exit 1 с hint). § 2: колонка `generate` по таблице выше.
`NOTES.md` «Реальные спеки»: таблица «Прогон 4.09 (второй)» — D1–D9 с решениями. `README.md:225-241`:
«прогоняет `analyze` и `generate`», две новые строки в таблице. `docs/TESTING.md` § 9: «`generate` — код из
таблицы, никакого `internal error`».

- [ ] **Step 5: Проверка и коммит**

Run: `bundle exec rake check && bundle exec rake real:generate`
```bash
git add Rakefile spec/real_specs_spec.rb .github/workflows/ci.yml docs/REAL_SPECS.md docs/TESTING.md NOTES.md README.md examples/real/reports
git commit -m "real specs: generate in the loop, Raiffeisen and Adyen Webhooks in the corpus, GENERATE.md report

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 9: `templates/service.rb.erb` < 200 строк

**Files:**
- Create: `templates/_process_callback.erb`, `templates/_helpers.erb`
- Modify: `templates/service.rb.erb`
- Modify: `docs/ARCHITECTURE.md` (Render: список partial), `docs/AUDIT.md` (§ 5 «templates/service.rb.erb 234 строки» — убрать)

- [ ] **Step 1: Вынести `process_callback` (строки 101–128) в `templates/_process_callback.erb`** — содержимое
блока переносится без изменений; в основном шаблоне на его месте `<%= partial('_process_callback.erb') -%>`.

- [ ] **Step 2: Вынести хелперы вне контракта (строки 129–158: комментарий `# --- Outside BaseService contract`,
`cancel_request`, `fetch_balance`) в `templates/_helpers.erb`**; в основном шаблоне `<%= partial('_helpers.erb') -%>`.

- [ ] **Step 3: Golden байт-в-байт**

Run: `bundle exec rspec spec/golden_spec.rb spec/renderers/service_spec.rb && wc -l templates/service.rb.erb`
Expected: 0 failures; ≤ 190 строк. Если появились лишние/пропавшие пустые строки — править `-%>` на границах
partial (как у `_rescues.erb`), **не** golden.

- [ ] **Step 4: Документация, проверка, коммит**

`docs/ARCHITECTURE.md` Render: перечислить partial'ы. `docs/AUDIT.md` § 5: удалить пункт о 234 строках.

Run: `bundle exec rake check`
```bash
git add templates docs/ARCHITECTURE.md docs/AUDIT.md
git commit -m "templates: split service.rb.erb into partials (< 200 lines), golden unchanged

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 10: Документы = факт

**Files:**
- Modify: `REQUIREMENTS.md`, `docs/AUDIT.md`, `docs/AUDIT_REPORT.md`, `CLAUDE.md`, `README.md`, `docs/AGENT_TASKS.md`

- [ ] **Step 1: `REQUIREMENTS.md`** (все пункты — уровень [FORGE], организаторские [ТЗ]/[QA] не трогать):
  - строки 504–505: «**ровно 5 предупреждений**» → «**ровно 6 записей** (3 WARN: `signature_encoding_assumed`,
    `conditional_required` ×2; 3 INFO: `outside_contract` ×2, `duplicate_as_success`) — NOTES D-06»;
  - строка 534 U-02 DoD: «Без overrides — 5 WARN + 4 INFO; с overrides — 0 WARN, 8 INFO (4 `override_applied`)»;
  - строка 524 V-01: `amount_unit` → `amount.unit` (`amount: { unit: minor|major, multiplier:, minimum_major: }`),
    `webhook.signature_encoding` и т. д. как есть; добавить `statuses.field`, `statuses.response_id`;
  - строка 526 V-03: «`examples/overrides/<provider>.yml` с комментариями; подсказка `hint:` с ключом overrides у
    каждого WARN в `report.txt` и в таблице «Допущения» `INTEGRATION.md` (отдельный `overrides.yml.example` — резерв R6)»;
  - строка 536 U-04: «(10 файлов)» и добавить `webhooks_only`;
  - § 7 «Быстрая проверка»: `bin/forge generate … cardpay.yaml --out tmp/cardpay  # 5 WARN + 4 INFO`, `… --overrides … # 0 WARN, 8 INFO`,
    добавить `bundle exec rake real   # analyze + generate на реальных спеках, без internal error`.
- [ ] **Step 2: `docs/AUDIT.md`**: § 3 `.mise.toml` → `mise.toml`; C3: «сетевой код — `rake real:fetch`, мок-сервер,
  `bin/e2e` и runtime-обёртка `lib/provider/http_client.rb` (при analyze/generate не вызывается)»; § 3 команда
  UPDATE_GOLDEN — примечание «rspec-процесс возвращает 2 из-за SimpleCov при одиночном запуске; критерий — пустой diff»;
  добавить `rake real` с `generate`.
- [ ] **Step 3: `docs/AUDIT_REPORT.md`**: «61/61» → «59/59»; «golden:176–177» → «golden:177–181»; № 9 и № 12 —
  «7 файлов на диске (6 контрактных + `generated_spec_helper.rb`)»; § 7 добавить п. 7 «второй прогон 4.09:
  `generate` на реальных спеках падал (D1–D2) — исправлено, см. план `docs/superpowers/plans/2026-09-04-hardening.md`».
- [ ] **Step 4: `CLAUDE.md`**: строка 90 — «строка в `overrides.yml.example`» → «`hint:` с ключом `overrides.yml`
  в отчёте и в «Допущениях» `INTEGRATION.md`»; M3 DoD — «на реальных спеках `analyze` и `generate` не падают».
- [ ] **Step 5: `README.md`**: «Ограничения» — пункты из T2/T3 (нет поля статуса → `in_progress` + TODO;
  discriminator `oneOf`; суммы в массивах); раздел «Быстрый старт» без изменений (проверяется `rake readme:check`).
- [ ] **Step 6: `docs/AGENT_TASKS.md`**: в «Резерв» добавить R6 (`overrides.yml.example` из структурированных hint),
  R7 (сумма и поля внутри массивов `items[]`); в «Остаток» — карточки из T8 Step 3, если были exit 3.
- [ ] **Step 7: Проверка и коммит**

Run: `bundle exec rake readme:check && bundle exec rake check`
```bash
git add REQUIREMENTS.md docs CLAUDE.md README.md
git commit -m "docs: align REQUIREMENTS, AUDIT, CLAUDE.md and README with the implementation

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
```

---

### Task 11: Релиз 1.1.0

**Files:**
- Modify: `lib/forge/version.rb`, `spec/golden/**` (регенерация), `spec/reference_spec.rb` (если проверяет версию), `docs/OUTPUT_FORMAT.md:38`

- [ ] **Step 1: Версия** — `VERSION = '1.1.0'`.
- [ ] **Step 2: Golden осознанно**

```bash
UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb; git diff --stat spec/golden
git diff spec/golden | grep '^[-+]' | grep -v '^[-+][-+]' | grep -v 'forge 1\.[01]\.0' ; echo "^ должно быть пусто: меняется только номер версии"
```
Expected: diff только в строках `Generated by forge 1.0.0` → `1.1.0` (и `"forge": "1.0.0"` в `fixtures.json`).
Любая другая строка в diff — регрессия, вернуться к соответствующей задаче.

- [ ] **Step 3: Полный CI локально и корпус**

Run: `bundle exec rake ci && bundle exec rake real`
Expected: rubocop 0; rspec 0 failures, покрытие ≥ 90 % / 75 %; determinism ok; licenses ok; readme:check ok; real без abort.

- [ ] **Step 4: Свежий клон + Docker (P-05)**

```bash
S=$(mktemp -d); git clone -q . "$S/forge" && cd "$S/forge" && bundle install --quiet && \
  bin/forge generate --spec examples/specs/novapay.yaml --out output/novapay && cd - && rm -rf "$S"
docker build -t forge . && docker run --rm -v "$PWD/examples:/app/examples" -v "$PWD/tmp:/app/tmp" forge generate --spec examples/specs/novapay.yaml --out tmp/d --force
```

- [ ] **Step 5: Коммит и тег**

```bash
git add lib/forge/version.rb spec/golden docs/OUTPUT_FORMAT.md
git commit -m "release: forge 1.1.0 — hardening against real provider specs

Claude-Session: https://claude.ai/code/session_01CGnEAB9LjQM1MZEetsvJ5s"
git tag -a v1.1.0 -m 'forge 1.1.0 — hardening: no crashes on real specs, exit 70, path params, nested statuses, auth preference'
git log --format='%ci %d' -1    # раньше 2026-09-06 22:00 +0300
```
Push (`git push origin main --tags`) — решение человека: до стоп-кода вс 6.09 22:00 MSK.

---

## Self-review

**Покрытие дефектов:** D1 → T2 (`constant`, ветки шаблона); D2 → T3 (`base_lines`); D3 → T1; D4 → T4 (`PathSources`,
`negative_words`); D5 → T5; D6 → T6; D7 → T7; D8 → T3 (`container?` нормализация, `recipient_mapping`,
`requisite_type_enum_mismatch`); D9 → T2 Step 12; D10 → T8; D11 → T9; D12 → T10; D13 → T11.

**Согласованность имён:** `ServiceView#constant(name, hash, todo)` (T2) используется только в шаблоне;
`ServiceView#status_path?` (T2) и `ServiceSpec#status_path?` (T2) — одинаковая семантика (`op(:create).response_status_path.nil?`);
`Plan::PathSources.for / credential_key_of / fixture_credentials` (T4) — используются в `Builder`, `Runner`,
`ServicePaths`, `ServiceSpec`, `IntegrationDoc`, `Fixtures`; `OperationPlan#path_sources` (T4);
`Analyzers::Statuses#call(field_path:, id_path:)` (T2) — вызывается из `OverridesEdits#relocated` (T2);
`OverridesEdits.new(overrides, log, spec)` (T2) — единственный вызов в `OverridesApply#findings`;
`Analyzers::SchemaSearch.candidates(schema, wrappers, max_depth:)` (T5) — в `Statuses` и `Webhooks`;
`Forge::CLI::INTERNAL_EXIT/INTERNAL_HINT` (T1) — в `cli_spec` и `real_specs_spec` (T8) по тексту «internal error».
Формы спек `statusless_spec`, `discriminated_variants_spec`, `account_path_spec` живут в `spec/support/spec_shapes.rb`
и подключены глобально через `RSpec.configure`.

**Регрессионный контракт:** после каждой из T2–T9 golden и снапшоты трёх учебных спек не меняются; это проверяют
шаги «Golden байт-в-байт» и `rake check`. Единственное изменение golden — номер версии в T11.
