# Архитектура forge

Шесть стадий, одна направленная цепочка данных. Стадии не знают о соседях дальше чем на шаг:
парсер не знает о Ruby-коде, шаблоны не знают об OpenAPI. Это и есть критерий «логика генерации
отделена от особенностей провайдера».

```
                 rules/*.yml                overrides.yml
                     │                           │
provider_api.yaml ─▶ Load ─▶ IR ─▶ Analyze ─▶ Plan ─▶ Render ─▶ Verify ─▶ Report
                      │             │           │        │         │
                  SpecError     Findings  IntegrationPlan  files  ruby -c / rspec
```

## Структура репозитория

```
forge/
├── bin/
│   ├── forge                      # Thor CLI (Ruby)
│   ├── integrate                  # обёртка с флагами ТЗ → forge generate --out ./output
│   ├── e2e                        # мок-сервер + сгенерированный сервис + webhook (M4)
│   └── demo                       # сценарий питча (M5)
├── lib/
│   ├── forge.rb                   # require всего
│   ├── forge/
│   │   ├── version.rb  errors.rb  cli.rb  report.rb  verifier.rb
│   │   ├── loader.rb              # файл → hash, версия, server variables
│   │   ├── ref_resolver.rb        # локальные JSON-pointer ссылки (~0/~1), циклы, внешние
│   │   ├── ir/                    # spec.rb server.rb security_scheme.rb endpoint.rb parameter.rb
│   │   │                          # request_body.rb response.rb schema.rb builder.rb
│   │   ├── rules.rb               # загрузка rules/*.yml (один раз, frozen)
│   │   ├── analyzers/             # base.rb runner.rb endpoint_roles.rb auth.rb statuses.rb
│   │   │                          # errors.rb webhooks.rb amount.rb fields.rb
│   │   ├── plan/                  # integration_plan.rb builder.rb overrides.rb naming.rb validations.rb
│   │   ├── fixtures/synthesizer.rb
│   │   ├── renderers/             # base.rb runner.rb service.rb service_spec.rb integration_doc.rb
│   │   │                          # fixtures.rb mock_server.rb report_file.rb
│   │   └── generated_spec_helper.rb   # копируется в output рядом со spec
│   └── provider/                  # контракт-заглушка (docs/CONTRACT.md)
│       ├── errors.rb result.rb operation.rb memory_operations.rb http_client.rb base_service.rb
├── rules/                         # словари (docs/RULES.md)
├── templates/                     # *.erb (docs/OUTPUT_FORMAT.md)
├── examples/
│   ├── specs/                     # novapay.yaml cardpay.yaml swiftpay.json
│   ├── overrides/                 # novapay.yml cardpay.yml swiftpay.yml
│   └── real/                      # reports/*.txt (коммитим), *.json|yaml (скачиваются, gitignore)
├── spec/                          # см. docs/TESTING.md
├── docs/  Rakefile  Gemfile  Dockerfile  .rubocop.yml  .rspec  .github/workflows/ci.yml
├── README.md
```

## CLI

```
bin/forge analyze  --spec FILE [--overrides FILE] [--include-paths GLOB]... [--format text|json] [--debug]
bin/forge generate --spec FILE [--provider NAME] [--out DIR] [--overrides FILE] [--include-paths GLOB]...
                   [--templates-dir DIR] [--lang ruby] [--format text|json]
                   [--strict] [--no-verify] [--force] [--debug]
bin/forge mock     --spec FILE [--port 4567] [--webhook-url URL] [--overrides FILE]
bin/forge version
bin/integrate      --spec FILE --provider NAME [--lang ruby]      # → forge generate --out ./output
bin/e2e            SPEC [--overrides FILE]                        # exit 0 = operation approved
```

| Код выхода | Когда |
|---|---|
| 0 | Успех (WARN/UNSUPPORTED/INFO допустимы) |
| 1 | Ошибка входа: файл не найден, не YAML/JSON, не OpenAPI 3.x, нерезолвимый `$ref`, цикл, внешний `$ref` в критичном месте, нет `paths`, неизвестный ключ overrides, `--lang` ≠ ruby |
| 2 | Ошибка генерации: нет create-эндпоинта, шаблон не найден, каталог вывода непустой без `--force` |
| 3 | Сгенерированный код не прошёл `ruby -c` или его spec красный |
| 4 | `--strict` и есть хотя бы один WARN/UNSUPPORTED |

`--include-paths` — glob по пути (`/v1/payouts*`), повторяемый; ограничивает анализ (для больших спек).
Эквивалент в overrides: `paths.include`.

## Стадия 1 — Load

`Forge::Loader.load(path) → Hash` (ключи-строки).

- `.yaml/.yml` → `YAML.safe_load(permitted_classes: [Date, Time], aliases: true)`; `.json` → `JSON.parse`;
  иначе — YAML, затем JSON. Пустой файл → `SpecError 'empty document'`; корень не Hash → `'root must be an object'`.
- Проверки: есть `openapi`, начинается с `3.`; `swagger: '2.0'` → `SpecError` «Swagger 2.0 is not supported;
  convert to OpenAPI 3»; `paths` — Hash, непустой.
- Server variables: `https://{env}.x/api` + `variables.env.default` → подстановка; enum-варианты сохраняются
  как альтернативные URL (`INFO server_variables`).
- `RefResolver.resolve(hash)`: `{'$ref' => '#/a/b'}` → цель, рекурсивно; JSON-pointer с `~0`/`~1`;
  защита от циклов (стек pointer'ов; цикл → `SpecError` с цепочкой); имя схемы → `x-forge-ref-name`.
  Внешние ссылки (`other.yaml#/…`, `http…`): в схеме запроса create или в `securitySchemes` — `UnsupportedError`
  (фатально); в остальных местах — заменяются на `{}` + `Warning(:unsupported, 'external_ref')`.
  Решение «критично/нет» принимает `Loader`, зная роль эндпоинта? Нет — Load не знает ролей. Поэтому
  Resolver помечает место (`x-forge-unresolved: <ref>`), а `Analyzers::Fields` превращает пометку в
  фатальную ошибку, если она в запросе create. (Решение D-05.)
- Каждая ошибка несёт путь файла и JSON-pointer.

## Стадия 2 — IR

Неизменяемые `Data.define` в `Forge::IR`. Никаких платёжных понятий.

```ruby
Spec           = Data.define(:title, :version, :openapi_version, :description, :servers,
                             :security_schemes, :default_security, :endpoints, :webhooks, :schemas, :source_path)
Server         = Data.define(:url, :description, :alternatives)   # alternatives: [url] из enum variables
SecurityScheme = Data.define(:name, :type, :location, :param_name, :scheme, :bearer_format, :description)
                 # type: 'apiKey' | 'http' | 'oauth2' | 'openIdConnect'; location: 'header' | 'query' | 'cookie'
Endpoint       = Data.define(:operation_id, :method, :path, :summary, :description, :tags,
                             :parameters, :request_body, :responses, :security, :callbacks, :pointer, :source)
                 # source: :paths | :callbacks | :webhooks; security: nil (унаследовано) | [] | [{name=>scopes}]
Parameter      = Data.define(:name, :location, :required, :schema, :description, :example)
RequestBody    = Data.define(:required, :media_type, :media_types, :schema, :examples)   # media_type — выбранный (json приоритет)
Response       = Data.define(:status, :description, :media_type, :schema, :examples, :headers)
Schema         = Data.define(:ref_name, :type, :format, :description, :properties, :required, :items,
                             :enum, :minimum, :maximum, :min_length, :max_length, :pattern, :multiple_of,
                             :example, :nullable, :one_of, :any_of, :all_of, :additional, :unresolved_ref)
```

`IR::Builder.build(hash, source_path:) → Spec`. Path-level `parameters` мержатся в операции. Security
по умолчанию (`spec.security`) подставляется, если у эндпоинта `security = nil`. `callbacks` каждой
операции и top-level `webhooks` превращаются в `Endpoint` с `source` ≠ `:paths`. `allOf` → слияние
`properties`/`required`; `oneOf`/`anyOf` сохраняются как есть; `type: ['string','null']` → `'string'` +
`nullable: true`. Несколько media type → `application/json`, затем `application/*+json`, затем первый.

## Стадия 3 — Analyze

```ruby
Finding = Data.define(:key, :value, :confidence, :source, :warnings)
Warning = Data.define(:level, :code, :message, :pointer, :hint)   # level: :warn | :unsupported | :info
```

Пороги в `rules/thresholds.yml` (см. `docs/RULES.md` § 0). Анализаторы и их выход:

| Анализатор | Выход (`value`) | Ключевые правила (полностью — RULES.md) |
|---|---|---|
| `EndpointRoles` | `{create:, status:, cancel:, balance:, webhook:, other: []}` | очки по сигналам и словам, `requires`, `negative_words`, один эндпоинт — одна роль, конфликт → WARN |
| `Auth` | `{type:, scheme_name:, header:, prefix:, credential_key:, location:}` | apiKey header → `api_key`; bearer → `token`; basic → `login`/`password`; oauth2 → UNSUPPORTED (bearer + TODO); apiKey query → WARN; альтернативы → первая поддерживаемая + UNSUPPORTED для остальных |
| `Statuses` | `{field_path:, map:, unmapped:, response_id_path:, response_status_path:}` | enum → словарь; без enum → из description (0.6 + WARN); wrapper `data` |
| `Errors` | `{http: {code => {provider_code:, internal_code:, action:, role:}}, codes: [], retry_after_header:}` | пример/enum → код; `codes`/`http` словари; схема успеха на 4xx → treat_as_success |
| `Webhooks` | `{endpoint:, source:, event_field:, event_map:, id_field:, status_field:, signature: {header:, algorithm:, encoding:, payload:, secret_key:}}` | paths → callbacks → webhooks; description → алгоритм/кодировка/payload; timestamp → UNSUPPORTED |
| `Amount` | `{field:, path:, unit:, multiplier:, minimum_major:, maximum_major:, currency_field:, currencies:, type:}` | маркеры описания, тип, minimum, pattern, multipleOf; default major + WARN |
| `Fields` | `{request: [FieldMapping], requisite_types:, requisite_container:, headers: [FieldMapping]}` | алиасы, контейнер реквизитов, required_if из description, unmapped → TODO + WARN |

```ruby
FieldMapping = Data.define(:provider_field, :path, :source_expr, :required, :required_if, :transform, :schema, :confidence)
```

`Analyzers::Runner.run(spec, rules:, include_paths: []) → Hash{key => Finding}`. Порядок фиксирован:
roles → auth → statuses → errors → webhooks → amount → fields.

## Стадия 4 — Plan

```ruby
IntegrationPlan = Data.define(
  :provider,      # {name:, class_name:, env_prefix:, title:}
  :base_url,      # {default:, production:, env_var:}
  :auth,          # из Auth
  :operations,    # {create: OperationPlan, status: OperationPlan|nil, cancel: OperationPlan|nil, balance: OperationPlan|nil}
  :webhook,       # из Webhooks | nil
  :status_map, :unmapped_statuses,
  :event_map,     # {'payout.completed' => 'approved', …} | {}
  :error_map,     # {400 => {provider_code:, internal_code:, action:}, …} (для сервиса — без treat_as_success)
  :success_statuses,   # [201, 409]
  :amount,        # из Amount
  :requisite_types,    # ['sbp', 'card']
  :fields,        # из Fields
  :validations,   # [{field:, rule: :min|:max|:max_length|:pattern|:enum, value:, error_code:}]
  :gateway_config,     # [{external_method:, gateway:}] по одному на тип реквизитов
  :fixtures,      # Hash в форме fixtures.json
  :outside_contract,   # [{endpoint:, helper: 'cancel_request' | 'fetch_balance' | nil}]
  :warnings,      # [Warning] в порядке обнаружения
  :meta           # {spec_title:, spec_version:, spec_file:, forge_version:}   — без времени!
)
OperationPlan = Data.define(:role, :method, :path, :path_params, :headers, :body_encoding,
                            :success_statuses, :response_id_path, :response_status_path, :error_statuses)
```

`Plan::Builder.build(spec, findings, overrides:, provider_name:)`:
1. Имя провайдера: `--provider` → иначе `info.title` без стоп-слов (api, payout(s), service, rest, v\d+),
   snake_case; `Plan::Naming` даёт `class_name`, `env_prefix`, `file_name`.
2. Собрать структуры из findings; `Plan::Overrides.apply` — поле за полем, каждое → `Warning(:info, 'override_applied')`;
   неизвестный ключ → `SpecError` + did-you-mean.
3. `Plan::Validations` из схемы: `minimum`/`maximum` суммы (в мажорных), `maxLength` external_id,
   `pattern` телефона/IBAN, `enum` валюты.
4. `fixtures` из examples, недостающее — `Fixtures::Synthesizer`.
5. Нет create после overrides → `GenerationError` «no create endpoint; set endpoints.<operationId>: create in overrides».

## Стадия 5 — Render

`Renderers::Runner.render(plan, out_dir:, templates_dir: nil) → [paths]`. Каждый рендерер — класс с
`template_name` и `filename(plan)`; ERB `trim_mode: '-'`; нормализация (одна пустая строка между
методами, `\n` в конце). Поиск шаблона: `--templates-dir/<name>.erb` → `templates/<name>.erb`.
Отсутствие → `GenerationError`. Непустой `--out` без `--force` → `GenerationError`.

| Рендерер | Шаблон | Файл |
|---|---|---|
| `Service` | `service.rb.erb` + партиалы `_auth_headers.erb`, `_verify_signature.erb`, `_payload.erb`, `_recipient.erb` | `<name>_service.rb` |
| `ServiceSpec` | `service_spec.rb.erb` | `<name>_service_spec.rb` (+ копия `generated_spec_helper.rb`) |
| `IntegrationDoc` | `integration.md.erb` | `INTEGRATION.md` |
| `Fixtures` | без ERB: `JSON.pretty_generate` | `fixtures.json` |
| `MockServer` | `mock_server.rb.erb` | `mock_server.rb` |
| `ReportFile` | из `Report` | `report.txt` |

## Стадия 6 — Verify

`ruby -c` (через `Open3`) на сервисе, spec и моке — ошибка синтаксиса → `VerificationError` с выводом
(это баг шаблона, он должен всплывать громко, exit 3). Затем `bundle exec rspec <out>/<name>_service_spec.rb`
(отключается `--no-verify`); красный → exit 3 с хвостом вывода.

## Report

Формат — `docs/OUTPUT_FORMAT.md` § 6. Уровни: WARN → UNSUPPORTED → INFO. Длинные списки (например,
60 unmapped-статусов) сворачиваются: первые 10 и «… and 50 more (see report.json)».

## Ошибки

```ruby
module Forge
  class Error < StandardError
    attr_reader :pointer, :hint, :file
    def initialize(message, pointer: nil, hint: nil, file: nil)
  end
  class SpecError < Error; end          # exit 1
  class UnsupportedError < Error; end   # exit 1, если фатально; иначе превращается в Warning(:unsupported)
  class GenerationError < Error; end    # exit 2
  class InternalError < GenerationError; end  # exit 2: любое неожиданное исключение конвейера (GenerateCommand.guard)
  class VerificationError < Error; end  # exit 3
end
```

Формат: `error: <message> at <pointer> in <file>\n  hint: <what to do>`.

## Тестирование

См. `docs/TESTING.md`. Кратко: unit на мини-спеках, rules, reference, golden ×5, негативные ×10+,
snapshot, сгенерированные spec ×3, determinism, e2e ×2, real ×7 (тег).

## Что не делаем (и говорим об этом честно)

Swagger 2.0; внешние `$ref` (в критичных местах — ошибка); OAuth2-флоу (bearer с TODO); `oneOf`/`anyOf`
глубже первого уровня (первый вариант + WARN); XML-тела; multipart; GraphQL; статус-запрос через POST
с id в теле; batch-выплаты. Всё это — UNSUPPORTED/WARN в отчёте и раздел «Ограничения» README.
