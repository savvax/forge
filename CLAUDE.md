# forge — генератор интеграций платёжных провайдеров из OpenAPI

Хакатон Space Payments (3–6.09.2026), задача 1. Это главный контекст для кодового агента.
Читать целиком перед любой задачей. Детали — в `docs/` (карта ссылок внизу).
Человек (John) — Go-инженер с минимальным опытом Ruby: объясняй решения так, чтобы он мог
пересказать их экспертам за 2 минуты.

## Что строим

CLI на Ruby 3.3. Вход: OpenAPI 3.0/3.1 спецификация платёжного провайдера (YAML или JSON).
Выход в `output/<provider>/`:

| Файл | Назначение |
|---|---|
| `<provider>_service.rb` | Сервис по контракту `Provider::BaseService` (`docs/CONTRACT.md`) |
| `<provider>_service_spec.rb` | RSpec-тесты сервиса на WebMock и фикстурах |
| `INTEGRATION.md` | Гайд: авторизация, методы, статусы, ошибки, подпись webhook, **допущения** |
| `fixtures.json` | Примеры запросов, ответов, уведомлений, ожидаемые статусы операции |
| `mock_server.rb` | Sinatra-мок провайдера из той же спеки (e2e и демо) |
| `report.txt` | Что распознано, с какой уверенностью, что не поддержано |

Команды: `bin/forge analyze | generate | mock`, `bin/integrate` (флаги из ТЗ), `bin/e2e`.
Точный формат каждого файла — `docs/OUTPUT_FORMAT.md`. Никогда не «улучшай» формат по вкусу:
эталон ТЗ лежит в `spec/reference/novapay/`, и `spec/reference_spec.rb` проверяет его элементы.

## Жёсткие ограничения (нарушение = дисквалификация)

1. **Весь код на Ruby.** Никаких Python/Node/shell-скриптов с логикой. `bin/*` — Ruby с shebang.
   Dockerfile, Makefile отсутствует (используем Rakefile), YAML-конфиги и GitHub Actions — допустимы.
2. **Только open-source зависимости** (MIT/Apache/BSD). Список гемов — в разделе «Гемы». Новый гем —
   только после явного согласия человека. `rake licenses` печатает лицензии всех гемов.
3. **Инструмент не вызывает нейросети и LLM ни в каком виде.** Классификация — правила, словари
   (`rules/*.yml`), регулярные выражения, подсчёт очков. Одинаковый вход → байт-в-байт одинаковый
   выход. Никаких сетевых вызовов во время анализа и генерации (кроме `rake real:fetch`, который
   лишь скачивает спеки для тестов).
4. **Знание о конкретном провайдере не живёт в Ruby-коде.** Всё специфичное — в `rules/` или в
   `overrides.yml` пользователя. Строка `novapay`/`cardpay`/`swiftpay` в `lib/` — баг (исключения:
   `spec/`, `examples/`, `docs/`).

## Уточнения организаторов (QA 1, 3.09) — приоритет над любыми догадками

- Вход только OpenAPI; **только выплаты (payout)**. Депозиты не нужны.
- Доп. эндпоинты (balance, cancel, refund, list) **не входят в контракт**: в отчёте — «найдено, вне
  контракта» (`INFO outside_contract`), в сервисе — необязательные хелперы (`cancel_request`,
  `fetch_balance`), никогда не вместо четырёх методов контракта.
- **Неоднозначность не угадывать молча.** Из структуры спеки — автоматически. То, что лежит текстом в
  `description` (единицы суммы, условная обязательность, детали подписи), — WARN + TODO в коде +
  строка в `overrides.yml`. Overrides — общий механизм (`amount.unit`, `fields.<path>.required_if`,
  `webhook.signature_encoding`), это не привязка к провайдеру (подтверждено письменно).
- **`request_method` в `create_request(operation, request_method)` — не HTTP-метод.** Это логический
  тип действия: платёжный метод шлюза (`sbp`, `card`, `bank_account`) либо служебное `status`/`check`.
  HTTP-verb всегда из спеки. `status`/`check` делегируются в `fetch_status`.
- Реальный `Provider::BaseService` и harness не дадут. `lib/provider/base_service.rb` — наш контракт.
- Канон статусов, если в спеке нет таблицы: `pending`/`processing` → `in_progress`,
  `completed` → `approved`, `failed`/`cancelled` → `rejected`. Всё, что вне словаря, — WARN `unmapped_status`.
- Канон NovaPay (эталон для golden): сумма в копейках (×100); `bank_code` обязателен при `type=sbp`;
  подпись webhook `HMAC-SHA256(raw body, callback_secret)` → hex.
- Секреты (`api_key`, `callback_secret`, `token`, `login`/`password`) — из `credentials`, с пометкой
  «заполнить вручную» в `INTEGRATION.md`. Неподдерживаемый **критичный** элемент → явная ошибка с
  подсказкой; некритичный → `UNSUPPORTED` в отчёте, генерация продолжается.
- CLI достаточно, веб-интерфейс не делаем. Документация может быть на русском.

## Архитектура (не менять без явного решения человека)

```
Load ──▶ IR ──▶ Analyze ──▶ Plan ──▶ Render ──▶ Verify ──▶ Report
```

Стадии знают только о соседях. Парсер не знает о Ruby-коде, шаблоны не знают об OpenAPI.
Полное описание структур — `docs/ARCHITECTURE.md`; словари и confidence — `docs/RULES.md`.

- **Load** `lib/forge/loader.rb`, `ref_resolver.rb`: файл → Hash; `openapi: 3.x`; локальные `$ref`
  (с `~0`/`~1`); server variables → подстановка default. Ошибки — `Forge::SpecError` с pointer.
- **IR** `lib/forge/ir/*.rb`: неизменяемые `Data.define`. Ноль платёжных понятий.
- **Analyze** `lib/forge/analyzers/*.rb`: `Spec` → `Finding(value, confidence, source, warnings)`.
  Порядок: `endpoint_roles → auth → statuses → errors → webhooks → amount → fields`.
- **Plan** `lib/forge/plan/*.rb`: findings + `overrides.yml` → `IntegrationPlan`. Единственный вход рендереров.
- **Render** `lib/forge/renderers/*.rb` + `templates/*.erb`: шаблон видит только `IntegrationPlan`.
- **Verify** `lib/forge/verifier.rb`: `ruby -c` на всём сгенерированном; `rspec` на сгенерированном spec.
- **Report** `lib/forge/report.rb`: текст как в ТЗ + секции WARN / UNSUPPORTED / INFO с подсказками; `--format json`.

## Стандарты кода

- `# frozen_string_literal: true` в каждом файле. Ruby 3.3. Без метапрограммирования
  (`define_method`, `method_missing`, `instance_eval`, `send` с динамическим именем).
- Файлы < 200 строк, метод < 20 строк, один класс — одна ответственность. Никаких `utils.rb`/`helpers.rb`.
- Ошибки: `Forge::Error` → `SpecError` (exit 1), `UnsupportedError` (exit 1 или Warning), `GenerationError`
  (exit 2), `VerificationError` (exit 3). Сообщение: `"<что не так> at <pointer> in <file>\n  hint: <что сделать>"`.
  CLI без стектрейсов, если нет `--debug`.
- Неоднозначность → `Warning` в план + безопасная заглушка + строка в `overrides.yml.example`. Падать
  только когда генерировать нечего (нет create-эндпоинта).
- Детерминизм: никакого времени, случайных значений, путей машины в выходных файлах.
- **Тесты пишутся вместе с модулем.** Порог SimpleCov: line ≥ 90 %, branch ≥ 75 %, по файлу ≥ 70 %.
  Golden-тесты `spec/golden/<provider>/` сравниваются байт-в-байт. Обновлять — только осознанно
  (`UPDATE_GOLDEN=1`) и после просмотра диффа.
- `bundle exec rubocop` — 0 нарушений (`-A` допустим). `bundle exec rake check` = rubocop + rspec.
- Коммит после каждой зелёной задачи, на английском: `<module>: <what>` (`analyzers: auth, statuses, errors`).
- Никогда не коммитить `output/`, `tmp/`, `coverage/`, `examples/real/*.{json,yaml}`.

## Гемы

Runtime: `thor` (CLI); stdlib `erb`, `psych`, `json`, `openssl`, `securerandom`, `did_you_mean`, `open3`, `net/http`.
Сгенерированный код и заглушка контракта: `faraday`.
Мок-сервер: `sinatra`, `rackup`, `puma`.
Dev/test: `rspec`, `webmock`, `simplecov`, `rubocop`, `rubocop-rspec`, `rubocop-rake`, `rake`.
Обсудить перед добавлением: `json_schemer` (валидация фикстур по схеме, резервная задача R1).

## Рабочий цикл задачи (для агента)

1. Прочитать карточку `Txx` в `docs/AGENT_TASKS.md` и все разделы `docs/`, указанные в карточке.
   Не читать «на всякий случай» весь `docs/` — контекст дорог.
2. Проверить, чем владеет карточка (список файлов). Не трогать чужие файлы; если нужно — остановиться
   и спросить человека.
3. Сначала тесты (красные), затем реализация, затем `bundle exec rake check`.
4. Прогнать `bin/forge generate --spec examples/specs/novapay.yaml --out tmp/out --force`
   (когда команда уже есть) — она не должна сломаться.
5. Обновить `README.md`, если изменилось поведение CLI; добавить запись в `NOTES.md` → «Решения»,
   если принято архитектурное решение (формат ADR-lite там же).
6. В конце — 5–7 предложений человеку: что сделано, какие решения приняты, что проверить руками,
   как объяснить экспертам. Затем `git commit`.

Если задача не помещается в сессию — закончить на зелёном состоянии, записать остаток в карточку
(`docs/AGENT_TASKS.md`, подраздел «Остаток») и остановиться. Никаких «почти работает».

## Определение готовности этапов

- **M1 Analyze:** `bin/forge analyze --spec examples/specs/novapay.yaml` печатает 5 эндпоинтов с ролями
  и confidence, auth, статусы, ошибки, webhook + подпись, сумму; ровно 6 записей (3 WARN, 3 INFO);
  на битом YAML — понятная ошибка, exit 1.
- **M2 Generate NovaPay:** `bin/forge generate` создаёт сервис, его spec, `INTEGRATION.md`, `fixtures.json`,
  `report.txt`; всё проходит `ruby -c`; `spec/reference_spec.rb` и golden зелёные; сгенерированный spec зелёный.
- **M3 Universal:** те же команды на `cardpay.yaml` и `swiftpay.json` дают корректный вывод с WARN/UNSUPPORTED
  там, где ожидается (`docs/TEST_SPECS.md`); `overrides.yml` закрывает все WARN; на реальных спеках
  (`docs/REAL_SPECS.md`) `analyze` не падает и даёт осмысленный отчёт.
- **M4 Proof:** `bin/e2e examples/specs/novapay.yaml` — мок поднят, выплата создана, webhook получен, операция `approved`.
- **M5 Ship:** Docker, CI зелёный, README для жюри, покрытие ≥ 90 %, rubocop чистый, тег `v1.0.0`.

## Карта документов

| Файл | Зачем читать |
|---|---|
| `docs/TASK.md` | Условие задачи (сжато) |
| `docs/CRITERIA.md` | Рубрики экспертов и жюри → на что влияет каждая задача |
| `docs/PLAN.md` | План по дням, чек-поинты, риски, cut-list |
| `docs/PROCESS.md` | Методология: волны агентов, DoD, качество, документация |
| `docs/AGENT_TASKS.md` | Бэклог карточек T01–T21 (одна карточка = одна сессия агента) |
| `docs/agents/ROLES.md` | Роли агентов, владение файлами, параллельные worktree, промпты |
| `docs/ARCHITECTURE.md` | Стадии, IR, IntegrationPlan, CLI, коды выхода |
| `docs/CONTRACT.md` | `Provider::BaseService`, `Operation`, `HttpClient` — полный код заглушки |
| `docs/RULES.md` | Словари `rules/*.yml`, подсчёт confidence, формат `overrides.yml` |
| `docs/OUTPUT_FORMAT.md` | Точный формат 6 выходных файлов |
| `docs/SPEC_ANALYSIS_NOVAPAY.md` | Что именно должно быть распознано в эталонной спеке (числа для тестов) |
| `docs/TEST_SPECS.md` | CardPay, SwiftPay, битые спеки: ожидаемые WARN/UNSUPPORTED |
| `docs/TESTING.md` | Пирамида тестов, покрытие, golden, негативные, e2e |
| `docs/REAL_SPECS.md` | Реальные спеки (Stripe, Adyen, PayPal, Paystack, Square, Plaid): что ожидаем |
| `docs/QA_SESSION_1.md` | Ответы организаторов (источник истины по требованиям) |
| `NOTES.md` | Решения (ADR-lite) и обратная связь экспертов с чек-поинтов |
| `docs/AUDIT.md` | Досье для аудита: требования → реализация → команды проверки → осознанные отклонения |
