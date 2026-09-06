# Тестирование forge

Зачем читать: тесты здесь — спецификация. Карточка задаёт ожидаемые значения, агент пишет тест
первым, человек проверяет по зелёному `rake check`. Цель — максимальное осмысленное покрытие
(line ≥ 90 %, branch ≥ 75 %) без «тестов ради процента».

## 1. Уровни и где лежат

| Уровень | Каталог | Что проверяет | Скорость |
|---|---|---|---|
| Unit | `spec/loader_spec.rb`, `spec/ref_resolver_spec.rb`, `spec/ir/`, `spec/analyzers/`, `spec/plan/`, `spec/renderers/`, `spec/provider/` | один класс, мини-спеки из Ruby-литералов (`build_spec(paths: {...})`) | < 2 с |
| Rules | `spec/rules/` | каждый словарь: примеры синонимов, отрицательные примеры, пороги | < 1 с |
| Reference | `spec/reference_spec.rb` | элементы примера ТЗ присутствуют в выходе NovaPay | 1 с |
| Golden | `spec/golden_spec.rb` + `spec/golden/<case>/` | байт-в-байт для novapay, cardpay, cardpay_overrides, swiftpay, swiftpay_overrides | 3 с |
| Negative | `spec/cli_spec.rb` + `spec/fixtures/broken/` | класс ошибки, pointer, hint, код выхода, отсутствие стектрейса | 3 с |
| Snapshot | `spec/snapshots/*.txt|json` | текст `analyze` и `--format json` для трёх спек | 1 с |
| Generated | `output/<p>/<p>_service_spec.rb` (через `Verifier` и в CI) | сгенерированный сервис против фикстур (WebMock) | 2 с × 3 |
| Determinism | `spec/determinism_spec.rb` | два прогона `generate` → одинаковые sha256 | 3 с |
| e2e | `bin/e2e` (Ruby) | мок-сервер + сервис + webhook → `approved` | 10 с |
| Real | `spec/real_specs_spec.rb` (тег `:real`) | реальные спеки не роняют `analyze`; роли/auth как ожидается | 30–60 с |

`bundle exec rspec` по умолчанию исключает `:real` (`spec_helper`: `config.filter_run_excluding real: true`
если нет `REAL=1`). `rake real` включает.

## 2. Помощники (`spec/support/`)

- `spec_builder.rb`: `build_spec(**parts)` — минимальная валидная OpenAPI-hash с переопределяемыми
  частями (`paths:`, `security_schemes:`, `schemas:`), чтобы тесты анализаторов были короткими:
  ```ruby
  spec = build_spec(paths: { '/transfers' => { 'post' => { 'operationId' => 'createTransfer', 'requestBody' => body_json(props) } } })
  ```
- `finding_matchers.rb`: `have_role(:create).with_confidence(0.95)`, `have_warning(:unmapped_status).mentioning('ON_HOLD')`.
- `deep_subset.rb`: `expect(actual).to deep_include(reference_json)`.
- `cli_runner.rb`: `run_cli('analyze', '--spec', path) → [stdout, stderr, exit_code]` через `Open3`.
- `generated_output.rb`: `generate_to_tmp(spec, overrides: nil) → Pathname` (кэшируется на прогон).

## 3. Что обязательно покрыть в каждом модуле

| Модуль | Обязательные примеры |
|---|---|
| Loader | yaml, json, авто-определение; `swagger: 2.0`; пустой; не объект; нет `openapi`; нет `paths`; server variables |
| RefResolver | локальный ref; вложенный; `~0`/`~1` в pointer (`#/paths/~1transfer/post`); `x-forge-ref-name`; цикл; внешний (fatal vs warning в зависимости от места) |
| IR::Builder | path-level parameters мержатся; security по умолчанию из корня; `security: []`; `examples`+`example`; 3.1 `type: [..]`; `allOf` слияние; `oneOf` сохранён; `callbacks`; top-level `webhooks`; несколько media types → приоритет json |
| EndpointRoles | таблица NovaPay; список → other; конфликт → WARN; `--include-paths`; negative_words; `requires` |
| Auth | apiKey header; apiKey query → WARN; bearer; basic; oauth2 → UNSUPPORTED; несколько альтернатив → первая поддерживаемая; нет схем → WARN `no_auth` |
| Statuses | enum; статусы из description (Stripe-стиль); camelCase; unmapped; поле `state`; wrapper `data` |
| Errors | пример → код; enum → код; `errors.0.code`; `problem+json`; схема успеха на 4xx → treat_as_success; Retry-After |
| Webhooks | paths; callbacks; top-level webhooks; sha256/sha512; hex/base64; payload из description; timestamp → UNSUPPORTED; event enum; общий тип события; нет webhook → WARN |
| Amount | копейки; cents; kobo; string pattern; number multipleOf; default → WARN; exponent JPY; nested `amount.value` |
| Fields | все алиасы NovaPay/CardPay/SwiftPay; conditional required; unmapped → TODO; массив → WARN; credential field; вложенный контейнер |
| Plan | naming (`--provider "Nova Pay"`); валидации; overrides каждого ключа; неизвестный ключ + did-you-mean; нет create → GenerationError |
| Renderers | каждый шаблон с планом «максимум» (всё есть) и «минимум» (нет webhook, нет cancel, нет status, bearer, basic, major/minor) → `ruby -c` |
| Verifier | синтаксическая ошибка → VerificationError с выводом; rspec красный → exit 3 |
| CLI | все коды выхода; `--format json` валиден; `--debug`; `--force`; `--strict`; `--templates-dir` |
| Provider stub | см. `docs/CONTRACT.md` § 7 |

## 4. Golden-тесты

- Генерируются командой `UPDATE_GOLDEN=1 bundle exec rspec spec/golden_spec.rb` **только после**
  просмотра диффа (`git diff spec/golden/`). В CI переменная не задаётся — golden только сравниваются.
- Сравнение: нормализуем только `\r\n → \n`; всё остальное байт-в-байт.
- Golden не заменяет reference-тест: reference проверяет «есть ли элементы ТЗ», golden — «ничего не
  изменилось случайно».
- При изменении шаблона ожидается дифф во всех golden — это нормально; при изменении анализатора дифф
  должен быть только там, где ожидалось (и это ревью-вопрос).

## 5. Негативные тесты CLI

Каждая строка таблицы битых спек в `docs/TEST_SPECS.md` § 4 = один `it`. Проверяем: код выхода, что
stderr начинается с `error:`, содержит имя файла и (где есть) pointer и `hint:`, и **не содержит**
`.rb:` (стектрейс) без `--debug`.

## 6. Тесты сгенерированного кода

Сгенерированный `*_service_spec.rb` запускается тремя способами: `Verifier` при `generate` (можно
отключить `--no-verify`), job `generated-specs` в CI (`rake generate:all && rake generated:spec`),
и вручную (`bundle exec rspec output/novapay/novapay_service_spec.rb`). Шаблон spec обязан работать
с любым планом: ветки для отсутствующего webhook/cancel/status выражены через `if`/`pending` в ERB.

## 7. Детерминизм

`rake determinism`: `generate` дважды во временные каталоги, `sha256sum` всех файлов совпадает. Ловит
случайные UUID, время, порядок Hash по `object_id`, абсолютные пути.

## 8. e2e (`bin/e2e`)

Ruby-скрипт: поднимает `mock_server.rb` на свободном порту (`TCPServer.new(0)`), поднимает крошечный
Rack-приёмник webhook, создаёт `Provider::Operation`, вызывает `check_conditions` → `create_request` →
`fetch_status` → `POST /_simulate/<id>/completed` на мок → ждёт (≤ 5 с) `approved` в `MemoryOperations`
→ печатает шаги и `operation approved ✓`, exit 0; любое расхождение → exit 1 с диагностикой.
Запускается для novapay и cardpay в CI.

## 9. Реальные спеки

См. `docs/REAL_SPECS.md`. Тест на каждую спеку: `analyze` завершается кодом из таблицы ожиданий;
роли/auth совпадают; отчёт совпадает со снапшотом `examples/real/reports/<name>.txt` (снапшот
обновляется осознанно, как golden).

## 10. Покрытие

`spec/spec_helper.rb` запускает SimpleCov первым (`enable_coverage :branch`, `minimum_coverage line: 90,
branch: 75`, `minimum_coverage_by_file 70`). Исключения: `spec/`, `output/`, `tmp/`, `examples/`,
`bin/` (CLI покрывается через `Forge::CLI` напрямую). HTML-отчёт — `coverage/index.html`, артефакт CI.
Падение ниже порога = красный `rake check`, значит карточка не закрыта.

## 11. Фаззинг (`rake fuzz`)

Гарантия «ввод пользователя не роняет приложение» проверяется тремя скриптами в `spec/fuzz/` (не rspec, а
обычные Ruby-программы; красный = исключение вне `Forge::Error` или ответ 5xx):

- `fuzz:web` — корпус `spec/fuzz/corpus/*.yml` (≈90 битых спек, 15 overrides, 33 набора параметров формы) плюс
  генерируемые случаи (байты, BOM, CRLF, 2 МБ скаляр, 3000 уровней вложенности, 21 МБ загрузка, гонки с диском)
  против `Forge::Web::App` in-process. Новый случай = строка в YAML.
- `fuzz:mutate` — случайные структурные мутации спек из `examples/` (и до четырёх небольших реальных, если
  скачаны) и overrides с фиксированным `SEED` (по умолчанию 42, `ROUNDS=40` на спеку). `InternalError`
  считается отдельно и тоже красный: это значит, что Shape должен отвергать такой вход с pointer.
  Проблемные документы сохраняются в `tmp/fuzz/mutate/internal-*`.
- `fuzz:mock` — ≈9000 враждебных запросов (тело не-JSON, суммы любого типа, null-байты, огромные заголовки)
  к мок-серверам всех спек из `examples/`.

`rake fuzz` не входит в `rake check`, но входит в `rake ci` и в CI (≈20 с): ~1300 кейсов, детерминированно.
Больше прогонов — `ROUNDS=500 SEED=7 bundle exec rake fuzz:mutate`.

## 12. Что не тестируем

Реальные сетевые вызовы к провайдерам (их нет по условию), rubocop-стиль в сгенерированном коде
(проверяем `ruby -c` и его spec; rubocop на output — только `--display-only-fail-level-offenses`
в `rake generated:lint`, не блокирует).
