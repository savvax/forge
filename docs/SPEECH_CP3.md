# Выступление на чек-поинте — 7 минут, полный текст, демо и ответы на вопросы

Всё, что здесь написано, проверено 6.09 в чистом клоне (`docs/DEMO_CP.md`). Цифры — реальные.
Ruby-термины из текста и построчный разбор кода сервиса — в разделе 6 (для Go-инженера, с аналогиями).
Формат чек-поинта: показать и рассказать, насколько близко к финальной версии, ответить на вопросы,
задать свои. Наш ответ на «насколько близко»: **финальная версия готова, тег `v1.0.0`, все пять этапов
закрыты; остаток — полировка по вашим замечаниям.**

---

## 0. Подготовка за 15 минут до слота

1. Закоммитить рабочее дерево (21 файл + отчёты второй волны). Сейчас всё зелёное.
2. `docker build -t forge .` заранее (первый билд сегодня упал на сети). На демо только `docker run`.
3. Открыть три окна терминала шрифтом ≥ 16pt: **A** команды, **B** `tmp/demo/novapay/novapay_service.rb`,
   **C** `tmp/demo/novapay/INTEGRATION.md`. Прогнать `bin/demo --fast` один раз — вывод в `tmp/demo/` как бэкап.
4. В браузере вкладки: README «Критерий → где смотреть», `examples/real/reports/SUMMARY.md`, CI (зелёный бейдж).
5. Команды ниже — в истории shell в этом порядке (стрелка вверх, Enter). Каждая < 1 с.

```bash
bin/forge analyze --spec examples/specs/novapay.yaml
bin/forge generate --spec examples/specs/novapay.yaml --out tmp/demo/novapay --force
bundle exec rspec -I lib -I tmp/demo/novapay tmp/demo/novapay/novapay_service_spec.rb
bin/e2e examples/specs/novapay.yaml
bin/forge generate --spec examples/specs/cardpay.yaml --out tmp/demo/cardpay --force --strict; echo exit=$?
bin/forge generate --spec examples/specs/cardpay.yaml --overrides examples/overrides/cardpay.yml --out tmp/demo/cardpay --force --strict; echo exit=$?
bin/e2e examples/specs/raiffeisen.yaml
bin/forge analyze --spec examples/real/stripe.json --include-paths '/v1/payouts*' | tail -3
bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo exit=$?
bundle exec rake check
```

Если что-то ломается на живом показе: не чинить, сказать «вывод из этого же прогона утром лежит в
`docs/DEMO_CP.md`», открыть файл и идти дальше. Демо — не отладка.

---

## 1. План на 7 минут (тайминг)

| Мин | Блок | Критерий, который закрываем | На экране |
|---|---|---|---|
| 0:00–0:40 | Что построили и статус | 5 (понятность), 6 (структура) | README, схема шести стадий |
| 0:40–1:30 | `analyze` NovaPay | 1 (разбор спеки, 20 б.) | вывод analyze |
| 1:30–2:50 | `generate` + код сервиса + INTEGRATION.md | 2 (сервис, 25 б.), 3 (данные, 15 б.), 5 | generate, окно B, окно C |
| 2:50–3:30 | RSpec сгенерированного + e2e | 2 (доказательство), 5 | rspec, e2e `approved ✓` |
| 3:30–4:50 | CardPay strict → overrides; Райффайзен e2e | 4 (универсальность, 15 б.) | exit 4 → exit 0, approved |
| 4:50–5:40 | Stripe 8 МБ, сводка 20 API, битая спека | 4, 5, 6 (ошибки) | tail, SUMMARY.md, exit 1 |
| 5:40–6:20 | Качество: rake check, покрытие, Docker, CI | 6 (качество, 10 б.) | rake check |
| 6:20–7:00 | Что дальше, вопросы экспертам | — | README «Что дальше» |

Правило: говорить поверх вывода, не ждать. Все команды < 1 с, `rake check` — 14 с (запустить в начале
блока «Качество» и говорить, пока идёт).

---

## 2. Полный текст выступления

### 0:00 — Что построили (40 с)

«Добрый день. Мы делаем задачу 1 — генератор интеграций с провайдерами выплат из OpenAPI.
Инструмент называется forge, это CLI на Ruby 3.3.

Статус: **финальная версия готова, тег v1.0.0.** Все пять этапов нашего плана закрыты: разбор,
генерация для эталонной спеки, универсальность, сквозное доказательство и упаковка. Сегодня
показываю полный цикл, а потом — где именно в репозитории лежит каждый критерий.

Как это устроено — одна строка: Load → IR → Analyze → Plan → Render → Verify → Report. Шесть стадий,
каждая знает только о соседях. Парсер не знает о Ruby-коде, шаблоны не знают об OpenAPI. Всё знание о
платежах лежит в словарях `rules/*.yml`, а не в коде. Нейросетей внутри нет — только правила, словари
и подсчёт очков. Один и тот же вход даёт байт-в-байт одинаковый выход.»

### 0:40 — analyze (50 с)

*Команда 1.*

«Первое — разбор спеки. Вот эталонная NovaPay. forge нашёл пять эндпоинтов и каждому дал роль с
уверенностью: create 0.95, status 0.90, webhook 0.90. Отмена и баланс распознаны, но помечены
«вне контракта» — организаторы подтвердили, что в контракт входят только четыре метода, поэтому они
уходят в отдельный класс-хелпер.

Дальше: авторизация — API-ключ в заголовке, привязан к `credentials.api_key`. Статусы — пять
провайдерских сведены к трём внутренним. Ошибки — каждый HTTP-код получил действие: 429 — повтор с
Retry-After, 409 — идемпотентный дубль, считаем успехом. Подпись webhook — HMAC-SHA256 по сырому телу.
Сумма — целое в копейках, минимум 1000 рублей.

И самое важное — три WARN. Это не сбои. Это места, где спека говорит что-то **текстом в description**,
а не структурой: кодировка подписи, «bank_code обязателен только для СБП». Мы это применили, но честно
пометили и дали строку для `overrides.yml`. Принцип: неоднозначное не угадываем молча.»

### 1:30 — generate и код сервиса (80 с)

*Команда 2.*

«Генерация. Тот же отчёт, потом семь файлов: сервис по контракту `Provider::BaseService`, его RSpec,
гайд интеграции, фикстуры, мок-сервер провайдера и отчёт. Обратите внимание на строку Verifying:
forge сам прогоняет `ruby -c` по всем файлам и запускает сгенерированный RSpec — 15 примеров, ноль
ошибок — прямо внутри генерации.»

*Окно B — сервис.*

«Сам сервис. Сверху — всё, что извлечено из спеки, в виде констант: `BASE_URL` из ENV с дефолтом на
sandbox, `STATUS_MAP`, `EVENT_MAP` для событий webhook, `ERROR_MAP` по HTTP-кодам, единицы суммы
`AMOUNT_MULTIPLIER = 100`, минимум, заголовок подписи.

Ровно четыре метода контракта. `check_conditions` — проверки до запроса: минимум суммы, валюта,
длина внешнего id, наличие реквизита, формат телефона по паттерну из схемы. `create_request` —
строит тело по типу реквизита, СБП или карта, шлёт POST с Idempotency-Key из операции, классифицирует ответ.
`request_method` здесь — не HTTP-глагол, а логический тип: `status` делегируется в `fetch_status`,
как уточнили организаторы. `fetch_status` — GET и маппинг статуса. `process_callback` — проверяет
подпись по сырому телу, берёт статус из события или из поля, переводит операцию. Сетевые ошибки и
401/429/5xx — отдельные ветки `rescue` с кодами `provider.*`. Ничего провайдер-специфичного в шаблоне
нет — всё это подставлено из плана.»

*Окно C — INTEGRATION.md, раздел «Допущения».*

«Гайд: авторизация, что заполнить вручную — ключ и секрет callback; ENV для базового URL; таблица
методов; маппинг статусов; ошибки; подпись — с пояснением, как передать сырое тело, потому что
платформа передаёт разобранный JSON. И раздел «Допущения» — те самые три WARN, с источником и
строкой для overrides. Инженер, который берёт этот сервис, видит, что мы решили сами, а что он
должен подтвердить у провайдера.»

### 2:50 — доказательство (40 с)

*Команда 3.*

«RSpec сгенерированного сервиса: WebMock и фикстуры из примеров той же спеки. 201 — создание, 422, 401,
429 с retry_after, 5xx, делегирование status, webhook с валидной подписью — approved, с невалидной —
отказ. Тело запроса сверяется с примером провайдера из спеки.»

*Команда 4.*

«И сквозной прогон: из той же спеки поднимается мок провайдера, сервис создаёт выплату, спрашивает
статус, мок шлёт подписанный webhook — операция approved. Меньше секунды. Это и есть ответ на
«сервис формирует и отправляет запросы, обрабатывает ответы и уведомления».»

### 3:30 — универсальность (80 с)

*Команда 5.*

«Теперь другая спека — CardPay. Всё отличается: bearer вместо ключа, сумма строкой в рублях, статусы
`NEW/SUCCESS/ON_HOLD` в поле `state` под обёрткой `data`, webhook описан через `callbacks`,
HMAC-SHA512 в base64, отмены нет. Тот же генератор, ни одной правки кода. Пять WARN: `ON_HOLD` не в
словаре — мы намеренно не решаем за пользователя, куда его класть; поле `expiry` в формате MM/YY —
нет источника в операции. В строгом режиме — exit 4, но файлы всё равно сгенерированы: так CI
краснеет, а артефакты есть.»

*Команда 6.*

«Добавляем `overrides.yml` — это общий механизм, не привязка к провайдеру, подтверждён организаторами:
`ON_HOLD → in_progress`, выражение для expiry, sandbox URL. Ноль WARN, exit 0, каждое переопределение
отмечено в отчёте как `override_applied`.»

*Команда 7.*

«Третья спека в репозитории — SwiftPay, OpenAPI 3.1 в JSON с `oneOf` получателя и OAuth2: три
UNSUPPORTED, но генерация не падает. А это — реальная спека Райффайзенбанка по СБП, на русском,
со статусом внутри объекта и Redoc-расширениями `x-webhooks`. Сквозной прогон — approved.»

### 4:50 — реальные API и ошибки (50 с)

*Команда 8.*

«Stripe — 8 мегабайт, 594 эндпоинта. Флаг `--include-paths` ограничивает выплатами: create, status,
cancel, basic auth, статусы, сумма в центах — за 0.3 секунды.»

*Вкладка SUMMARY.md.*

«Всего прогнали 20 реальных спек: Adyen, PayPal, Paystack, Square, Plaid, Wise, Mollie, Dwolla и
другие. 19 — exit 0 с честными WARN. Square без create-эндпоинта — честный exit 2 с подсказкой.
GOV.UK Pay — Swagger 2.0 — exit 1 с советом конвертировать. Шесть сервисов из реальных спек проходят
свой RSpec и ходили в настоящие sandbox с неверным ключом: 401 → `invalid_credentials`. Этот прогон
вскрыл и закрыл десять дефектов генерации — они в `docs/AUDIT.md`.»

*Команда 9.*

«Битая спека — циклический `$ref`: ошибка с JSON-pointer, подсказка, exit 1, без стектрейса. Таких
негативных фикстур десять.»

### 5:40 — качество (40 с)

*Команда 10 — запустить и говорить.*

«Качество. Rubocop — ноль замечаний на 115 файлах. 257 тестов, покрытие 97.9 % по строкам, 84 % по
ветвям. Golden-тесты байт-в-байт для четырёх спек, с overrides и без. Проверка детерминизма — два
прогона, 30 файлов, идентичны. `guard:vendor` — в `lib/` нет ни одного имени провайдера. Docker, CI на
GitHub Actions делает всё то же плюс e2e и реальные спеки. 66 файлов в `lib/`, ни одного больше 240
строк, каталог на стадию.»

### 6:20 — что дальше и вопросы (40 с)

«Что дальше и чего осознанно не делаем: pay-in — вне задачи по уточнению организаторов, но пайплайн
тот же; Swagger 2.0 — через конвертацию; OAuth2-флоу и подпись с timestamp — TODO с пометкой, не
угадываем; batch-выплаты с массивами. Всё это — в README «Ограничения», честно.

У нас три вопроса: …» (см. раздел 4).

---

## 3. Вопросы и ответы — по критериям

Формат: вопрос → ответ за 20 секунд → что показать, если попросят доказательство.

### Критерий 1. Разбор спецификации (20)

**Как определяете, какой эндпоинт — create, а какой — status?**
Подсчёт очков по словарю `rules/endpoint_roles.yml`. Для create: POST 0.30, слово выплаты в пути 0.25,
слово создания 0.20, нет path-параметра 0.10, есть тело 0.10, штраф −0.25 за `{id}` в пути. Слова
нормализуются из camelCase и kebab-case. Пороги в `thresholds.yml`: ≥ 0.8 принято, 0.5–0.8 принято с
WARN `low_confidence`, ниже — WARN `needs_override`. Негативные слова (refund, order, health, invoice)
штрафуют. Показать: `rules/endpoint_roles.yml`, поле `source` в `--format json`.

**Что такое confidence 0.95 — откуда число?**
Сумма весов сработавших сигналов, обрезанная до 1.0. Это не вероятность, а объяснимый счёт: в JSON-отчёте
у каждого решения есть `source`, например «operationId 'createPayout' matches /payout/; POST without
path param».

**Как извлекаете параметры запросов и ответов?**
Обход схемы запроса с резолвом `$ref`, `allOf`, `oneOf`; каждое поле сопоставляется с полем операции
Space Payments по алиасам `rules/field_aliases.yml` (amount, currency, external id, реквизиты по типу).
Обязательность — из `required`, ограничения — из `minimum`, `maxLength`, `pattern`, `enum`. Ответ —
поле статуса и id ищутся по спискам `status_fields`/`id_fields` с учётом обёрток `data`/`result`.

**Авторизация: какие схемы поддерживаете?**
apiKey (header/query), http basic, http bearer — из `securitySchemes` и `security`. OAuth2 — UNSUPPORTED:
генерируем bearer с TODO, потому что флоу получения токена спека не описывает. Несколько схем —
берём первую поддержанную, остальные — INFO/UNSUPPORTED.

**Статусы: если у провайдера статус, которого нет в словаре?**
WARN `unmapped_status` с hint `statuses.X: in_progress|approved|rejected`. Словарь намеренно не содержит
двусмысленных `on_hold`, `returned`, `reversed` — это решение бизнеса, не инструмента. В сервисе
неизвестный статус в `fetch_status` даёт `unknown_provider_status`, а не тихий `in_progress`.

**Ошибки: как решаете, retry или reject?**
`rules/error_actions.yml`: по HTTP-коду и коду ошибки из схемы/примеров. 429 → retry с Retry-After,
5xx → retry, 4xx валидация → reject, 401 → alert_block, 409 с успешной схемой → treat_as_success.

**Webhook: откуда берёте?**
Четыре источника по убыванию: явный путь `/webhooks/*` с пустым `security`, OpenAPI `callbacks`,
top-level `webhooks` (3.1), Redoc `x-webhooks`. Подпись — заголовок по словарю
`webhook_signature.yml` плюс алгоритм из description (sha256/sha512, hex/base64). Что не сказано —
WARN `signature_encoding_assumed` / `signature_payload_assumed`.

**Что с условиями типа «поле обязательно, если type=sbp»?**
Из текста description — регулярка, применяется как `required_if` в `check_conditions`, но WARN
`conditional_required`, потому что текст — не структура. Пользователь подтверждает через overrides.

### Критерий 2. Генерация сервиса (25)

**Покажите, где сервис отправляет запрос.**
`create_request`: `client.post("#{BASE_URL}/payouts", json: payload, headers: auth_headers.merge(idempotency_headers))`.
`client` — `Provider::HttpClient` на Faraday с таймаутами, который переводит 401/429/5xx/сетевые сбои
в исключения `Provider::*Error`, а сервис ловит их в `rescue` и возвращает `failure(:код, 'provider.*')`.

**Что такое `Provider::BaseService`? Вам его давали?**
Нет, организаторы сказали, что реальный класс и harness не дадут. `lib/provider/base_service.rb` —
наш контракт по ТЗ: `check_conditions`, `create_request`, `fetch_status`, `process_callback`,
`success/failure`, `approve_operation/reject_operation`, `transition` с `result[:id]` и
`provider_operation_key` — по уточнению QA 2. Полный код — `docs/CONTRACT.md`. Заменить на реальный —
один файл.

**Как обрабатываются ответы и статусы?**
`parse_create_response`: код в `SUCCESS_STATUSES` → берём id по `id_fields`, статус через `STATUS_MAP`,
переводим операцию (`in_progress` по умолчанию, итог придёт через status/webhook). Не успех → код из
`ERROR_MAP` или из тела. `fetch_status` — `apply_status(strict: true)`.

**Входящие уведомления: как проверяется подпись, если платформа даёт разобранный JSON?**
`process_callback(payload, raw_body: nil, headers: {})` — сигнатура из ТЗ остаётся валидной. С
`raw_body` подпись считается по байтам; без него — по `JSON.generate(payload)` с явным предупреждением в
INTEGRATION.md, что сойдётся только при компактном JSON. Организаторы в QA 2 это подтвердили.

**Настройка параметров подключения?**
`BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', sandbox)`, `PRODUCTION_URL` рядом; секреты — `credentials.*`
с пометкой «заполнить вручную»; `config.callback_url`; ProviderGateway config в INTEGRATION.md.
Если в спеке нет sandbox-сервера — WARN `production_default`.

**Идемпотентность, повторы, таймауты?**
Idempotency-Key = `operation.idempotency_key` (UUID, который платформа хранит у операции; в заглушке контракта он создаётся при первом обращении); заголовок добавляется, только если спека его объявляет. Повторы — не в сервисе,
а на стороне платформы: сервис возвращает `retry_after` и код `provider.rate_limit`/`provider.unavailable`.
Таймауты — в HttpClient.

**Куда делись cancel и balance?**
Эксперты на CP2 попросили держать в сервисе только контракт. Они в `<provider>_extras.rb`,
`NovapayExtras < NovapayService`; файл не создаётся, если таких эндпоинтов нет. INFO `outside_contract`.

### Критерий 3. Преобразование данных (15)

**Как сопоставляются поля?**
Алиасы в `rules/field_aliases.yml`: `amount`, `currency`, `external_id/reference/order_id`, реквизиты по
типу (`phone`+`bank_code` для СБП, `card_number` для карты, IBAN для счёта). Контейнер типа реквизита
(`recipient`, `payoutParams`) и значение типа (`SBP` → `sbp`) матчатся по нормализованному имени. Поле
без источника → WARN `unmapped_field` + `nil` + hint `fields.<path>.source`. Массивы — WARN, не мапим.

**Единицы суммы?**
`rules/amount_units.yml`: тип integer + маркеры в description (копейки, cents, minor) → ×100 через
`AMOUNT_MULTIPLIER`; экспонента валюты из `currency_exponents.yml`; строка → `format('%.2f')`; число →
`round(2)`. Минимум из схемы пересчитывается в мажорные единицы для `check_conditions`. Спорно → WARN +
`amount.unit` в overrides.

**Обязательные и необязательные поля?**
Обязательные проверяются в `check_conditions` до запроса; необязательные без значения удаляются
`deep_compact`, чтобы не слать `null`. Условные — `required_if`. Ограничения `maxLength`/`pattern` —
тоже в `check_conditions`.

**Форматы: даты, MM/YY, плоские реквизиты карты?**
Форматные поля без источника получают WARN и выражение через overrides `source:` (пример expiry в
CardPay). Плоская форма `payout_requisite['card_number']` поддержана по QA 2 — это знание о платформе,
поэтому живёт в шаблоне, а не в rules.

**`oneOf` получателя?**
Первый вариант + WARN `one_of_first_variant`; выбор — `fields.<path>.variant: <SchemaName>`.

### Критерий 4. Универсальность (15)

**Чем докажете, что логика не привязана к NovaPay?**
Три вещи. `rake guard:vendor` в CI падает, если в `lib/` встречается имя провайдера. Четыре спеки в
репозитории с golden-тестами байт-в-байт, включая реальную Райффайзен. 20 реальных API, 19 — exit 0,
шесть сервисов из них проходят собственный RSpec.

**Как добавить новое правило?**
Без Ruby: строка в `rules/*.yml` — новый синоним статуса, новое слово роли, новый алиас поля, новый
заголовок подписи. `docs/RULES.md` § 10 — пошагово. Правила загружаются один раз через `Forge::Rules`
(кэш по имени файла, глубокая заморозка), словари покрыты `spec/rules/rules_spec.rb`. Шаблоны тоже подменяемы: `--templates-dir`.

**Неподдерживаемый элемент — что происходит?**
Три уровня. Некритично — `UNSUPPORTED` в отчёте, заглушка в коде (`{}` для внешнего `$ref`,
`NotImplementedError` с пояснением для подписи с timestamp), генерация продолжается. Критично — только
когда генерировать нечего: нет create → exit 2, внешний/циклический `$ref` в схеме запроса create → exit 1.
Всегда с hint, что сделать.

**Overrides — это не костыль под конкретного провайдера?**
Нет: ключи общие (`amount.unit`, `statuses.<X>`, `fields.<path>.required_if|source|variant`,
`webhook.signature_*`, `endpoints.<opId>: role`, `paths.include`). Организаторы письменно подтвердили,
что это правильный механизм для того, что лежит текстом в description. Каждое применение — INFO
`override_applied`, всё видно в отчёте.

**Большие спеки?**
Stripe 8 МБ: кэш целей `$ref` и мемоизация схем — 0.3 с. `--include-paths` / `paths.include` для
фокуса; при конфликте ролей отчёт сам подсказывает флаг.

**Другие языки, кроме Ruby?**
`--lang ruby` — единственный. Архитектурно шаблон видит только `IntegrationPlan`, поэтому второй
`templates-dir` для другого языка — работа над шаблонами, не над анализом. Не делали, не в задаче.

### Критерий 5. Понятность и демонстрация (15)

**Как запустить с нуля?**
`bundle install`, потом `bin/integrate --spec provider.yaml --provider name --lang ruby` — команда из ТЗ,
результат в `output/<provider>/`. Или Docker. README — секция «Быстрый старт», `rake readme:check`
проверяет, что команды из README реально работают.

**Что читать инженеру, который берёт сервис?**
`INTEGRATION.md`: авторизация и что заполнить вручную, ENV, методы, статусы, события, ошибки, подпись с
инструкцией про raw body, поля запроса, «Вне контракта», «Допущения», «Проверка». Плюс `report.txt` и
`fixtures.json` с примерами и ожидаемыми статусами операции.

**Коды выхода?**
0 — ок; 1 — спека (SpecError/UnsupportedError критичный); 2 — генерация (нет create); 3 — верификация
(`ruby -c`/rspec сгенерированного); 4 — `--strict` при WARN/UNSUPPORTED, файлы при этом созданы.
`--format json` для машин, `--debug` для стектрейса.

**Веб-интерфейс?**
Есть тонкая обёртка `bin/forge-web` (Sinatra, те же классы, без БД) — загрузить спеку, увидеть отчёт,
скачать файлы, запустить RSpec и e2e кнопкой. Организаторы сказали, что CLI достаточно, поэтому это
только для демо.

### Критерий 6. Качество реализации (10)

**Структура кода?**
Каталог на стадию: `loader.rb`/`ref_resolver.rb` → `ir/` (неизменяемые `Data.define`) → `analyzers/`
(семь анализаторов, каждый возвращает `Finding(value, confidence, source, warnings)`) → `plan/`
(единственный вход рендереров, overrides, валидации, фикстуры) → `renderers/` + `templates/*.erb` →
`verifier.rb` → `report.rb`. 66 файлов, ни одного > 240 строк, без динамического метапрограммирования (`define_method`, `method_missing`, `instance_eval`; единственный `public_send` — по фиксированному списку ключей overrides).

**Обработка ошибок разбора и генерации?**
Иерархия `Forge::Error` → `SpecError`, `UnsupportedError`, `GenerationError`, `VerificationError`.
Формат: `error: <что> at <pointer> in <file>` + `hint:`. Десять негативных фикстур в
`spec/fixtures/broken/`, тесты CLI на каждую. Циклический и битый `$ref` — маркер, а не падение
загрузчика: фатально только в схеме запроса create.

**Тесты?**
257 примеров: юнит на каждый анализатор с числами из `docs/SPEC_ANALYSIS_NOVAPAY.md`, snapshot вывода
`analyze`, golden байт-в-байт для четырёх спек, reference-тест на элементы эталона из ТЗ, determinism,
e2e, CLI, веб. SimpleCov: 97.9 % / 84.4 %, порог в CI 90 / 75.

**Как разрабатывали? AI-ассистированно?**
Да, это разрешено правилами. Человек — постановка, карточки задач с ожидаемыми значениями
(`docs/AGENT_TASKS.md`), ревью диффов, golden только после просмотра. Инструмент сам нейросети не
использует — это проверяемо: ни одного сетевого вызова в `lib/`, кроме Faraday в сгенерированном коде.

### Ловушки и острые вопросы

**«Почему не LLM? Было бы точнее».** Во-первых, запрещено условием. Во-вторых, для платёжной интеграции
важнее объяснимость: каждое решение имеет `source`, воспроизводится и покрывается тестом. Ошибка в
единицах суммы — это деньги; «вероятно копейки» от модели хуже, чем WARN и строка overrides.

**«У вас 104 WARN на Adyen Transfers — это же провал».** Это 100+ редких статусов из enum, которых нет в
словаре, и отчёт их сворачивает. Роли, auth, сумма распознаны на 0.95/0.90. WARN — честность: каждый
закрывается одной строкой. Альтернатива — молча положить `reversed` в `approved`.

**«Что отделяет вас от 100 баллов?»** Три известных ограничения: OAuth2-флоу, подпись с timestamp и
batch-массивы — TODO, не генерация. Всё остальное по разбалловке закрыто и показано. Хотим услышать от
вас, что ещё.

**«Сколько времени на нового провайдера?»** Генерация — секунда. Человек — прочитать «Допущения»,
заполнить `credentials`, при необходимости 3–5 строк overrides, прогнать e2e на моке, потом sandbox.
Часы вместо дней.

**«request_method — это HTTP-метод?»** Нет, по уточнению организаторов это логический тип действия:
`sbp`/`card`/`bank_account` или служебные `status`/`check`. HTTP-глагол всегда из спеки.

**«Мок-сервер — зачем?»** Доказательство и демо: генерируется из той же спеки, отдаёт 401/422/409 по
её примерам, умеет прислать подписанный webhook. e2e `create → webhook → approved` без реального
провайдера.

**«Что, если спека без примеров?»** `Fixtures::Synthesizer` строит примеры из схемы (типы, enum,
минимумы); примеры из спеки сверяются со схемой (INFO `fixture_schema_mismatch`). В NovaPay нашли
реальное расхождение в самом ТЗ: пример 401 не входит в enum кода ошибки.

**«Депозиты?»** Организаторы: только выплаты. Pay-in спеки (Kaspi, Klarna) анализируются честно с
низким confidence и WARN — не путаем приём платежа с выплатой (Square `POST /v2/payments` штрафуется).

**«Можно развернуть у себя?»** `git clone`, `bundle install`, `rake check` — 14 с. Или `docker build`.
Утром проверено в чистом клоне: `docs/DEMO_CP.md`.

---

## 4. Пять тезисов (если останется 30 секунд) и вопросы экспертам

Тезисы:
1. Шесть стадий, каждая знает только о соседях; знание о платежах — в `rules/*.yml`, `guard:vendor` это охраняет.
2. Никаких нейросетей: словари и подсчёт очков, `Finding` с confidence и `source` — объяснимо, детерминированно, тестируемо.
3. Неоднозначное не угадываем: структура → автоматически, description → WARN + TODO + строка overrides + «Допущения».
4. Overrides — общий механизм, подтверждённый организаторами; каждое применение видно в отчёте.
5. Доказательства, а не обещания: сгенерированный RSpec, мок + e2e до `approved`, 20 реальных API, golden байт-в-байт.

Вопросы экспертам:
1. Формат сдачи и защиты: публичность репозитория, тег `v1.0.0` достаточно, кто из команды выступает?
2. Что, по-вашему, отделяет текущее состояние от максимума по критериям 2 и 4 — есть ли элемент разбалловки, который мы не показали?
3. Хелперы вне контракта в отдельном классе `Extras` и `--strict` как exit 4 в конце — так, как вы просили на CP2? Что-то ещё из замечаний осталось незакрытым?

---

## 5. Cut-list: что резать, если на демо что-то не работает

Сейчас не работает ничего из проекта; единственный риск — сеть (Docker pull). Если всё-таки:

| Симптом | Что делать в моменте | Что режем |
|---|---|---|
| Docker не собирается | не показывать build, есть образ `forge:latest` с пятницы: `docker run --rm forge analyze …` | пункт «Docker с нуля», остаётся CI-лог |
| e2e не стартует (порт, puma) | открыть `docs/DEMO_CP.md` § 5, показать RSpec сгенерированного — он и есть доказательство | живой e2e → скринкаст/лог |
| `rake check` дольше 30 с | не ждать, показать CI-бейдж и `coverage/` из утреннего прогона | живой rake check |
| Stripe нет в `examples/real/` (не в git) | `bundle exec rake real:fetch` заранее; иначе `examples/real/reports/stripe.txt` | живой Stripe → снапшот |
| Слот сократили до 5 минут | блоки 0:00, 0:40, 1:30, 2:50, 3:30 (только CardPay) и тезисы | реальные API и качество — одной фразой с ссылкой на README |

Никогда не режем: analyze NovaPay, generate + код сервиса, сгенерированный RSpec, «Допущения», exit 4 → exit 0 на CardPay.

---

## 6. Ruby-термины из этого текста — что это и как сказать одной фразой

Для Go-инженера: слева термин, справа что это, аналогия из Go и фраза, которую можно произнести
эксперту, не запинаясь. Термины идут в порядке появления в выступлении.

### Инструменты и экосистема

| Термин | Что это | Аналогия из Go | Как сказать |
|---|---|---|---|
| **gem** | Пакет Ruby. Список — `Gemfile`, точные версии — `Gemfile.lock`. | модуль в `go.mod` / `go.sum` | «Зависимости — только open-source гемы, `rake licenses` печатает лицензии всех 52.» |
| **Bundler, `bundle install`, `bundle exec`** | Менеджер зависимостей. `bundle exec X` запускает X с версиями из `Gemfile.lock`. | `go mod download`; `bundle exec` ≈ гарантия, что запускается ровно тот набор версий | «Всё запускается через `bundle exec`, чтобы версии совпадали с lock-файлом.» |
| **Rake, `Rakefile`, `rake check`** | Task-runner на Ruby; задачи описаны кодом. Makefile нам нельзя, поэтому Rakefile. | Makefile, но на Ruby | «`rake check` — lint, тесты и guard; `rake ci` — всё, что делает CI.» |
| **Thor** | Гем для CLI: подкоманды, флаги, `--help`. На нём `bin/forge`. | cobra | «CLI на Thor: `analyze`, `generate`, `mock`, флаги описаны декларативно.» |
| **RSpec** | Тестовый фреймворк. Тест = «example» (`it '…' do … end`), группа = `describe`. `pending` — тест объявлен, но ожидаемо не проходит, помечен жёлтым, не красным. | `testing` + testify; `t.Skip` с причиной ≈ `pending` | «257 примеров RSpec; сгенерированный сервис получает собственный spec на 15 примеров.» |
| **`*_spec.rb`** | Файл с тестами RSpec. `novapay_service_spec.rb` — тесты сервиса. | `*_test.go` | «Spec-файл — это тесты; не путать со спецификацией OpenAPI.» |
| **WebMock** | Гем, который перехватывает HTTP из тестов и подставляет заранее описанные ответы; настоящую сеть запрещает (`disable_net_connect!`). | `httptest.Server` / замена `http.RoundTripper` | «Сгенерированный spec ходит не в сеть, а в WebMock с ответами из фикстур.» |
| **Faraday** | HTTP-клиент. Обёрнут в `Provider::HttpClient` с таймаутами 10 с / 5 с на соединение. | `net/http` + свой `Client` с `Timeout` | «Транспорт — Faraday; сервис его не видит, только наш `HttpClient`.» |
| **Sinatra, Puma, rackup** | Sinatra — микрофреймворк для HTTP (роуты в 10 строк). Puma — сервер. На них мок провайдера и веб-обёртка. | `net/http` + `http.HandleFunc`; Puma ≈ встроенный сервер | «Мок-сервер — Sinatra из той же спеки, поднимается за долю секунды.» |
| **RuboCop** | Линтер и форматтер. `rubocop -A` — автопочинка. | `gofmt` + `golangci-lint` | «RuboCop — ноль замечаний на 115 файлах.» |
| **SimpleCov** | Покрытие тестами: line (строки) и branch (ветви `if/else`). | `go test -cover`; branch-покрытие в Go из коробки нет | «Покрытие 97.9 % по строкам и 84 % по ветвям, порог в CI 90 / 75.» |
| **`ruby -c`** | Проверка синтаксиса файла без запуска. | `go vet` / `gofmt -e`, но только синтаксис | «Каждый сгенерированный файл проходит `ruby -c`, потом свой RSpec.» |
| **ERB** | Шаблонизатор: текст с вставками `<%= … %>` (вывести) и `<% … %>` (логика). `templates/service.rb.erb` — шаблон сервиса. | `text/template` | «Шаблон ERB видит только `IntegrationPlan`, ни строки OpenAPI.» |
| **Psych** | Стандартный парсер YAML. | `gopkg.in/yaml.v3` | «YAML и JSON читаются stdlib, без внешних парсеров.» |
| **`-I lib`** | Флаг `ruby`/`rspec`: добавить каталог в пути поиска `require`. | `GOPATH`/replace в `go.mod` | «`-I lib -I tmp/demo/novapay` — чтобы spec нашёл контракт и сервис.» |
| **golden-тест** | Не термин Ruby, а приём: сгенерированный файл сравнивается байт-в-байт с эталоном в `spec/golden/`. Обновляется только осознанно (`UPDATE_GOLDEN=1`). | golden files в `testdata/` | «Golden-тесты для четырёх спек, с overrides и без.» |
| **snapshot-тест** | То же для текстового вывода `analyze` (`spec/snapshots/`). | golden output | «Вывод analyze зафиксирован снапшотом, любое изменение формата — красный тест.» |

### Язык: что видно в коде сервиса

| Термин / синтаксис | Что это | Аналогия из Go |
|---|---|---|
| `module Provider` / `class NovapayService < BaseService` | `module` — пространство имён; `class A < B` — A наследует B. `Provider::NovapayService` — полное имя. | package + embedding: `type NovapayService struct{ BaseService }` |
| `# frozen_string_literal: true` | Магический комментарий: все строковые литералы в файле неизменяемы. Стандарт проекта. | строки в Go и так неизменяемы |
| `STATUS_MAP = { … }.freeze` | Константа (с большой буквы) — хеш; `.freeze` делает его неизменяемым. | `var statusMap = map[string]string{…}`; freeze ≈ «только чтение» |
| `%w[sbp card]` | Литерал массива строк: `['sbp', 'card']`. | `[]string{"sbp", "card"}` |
| `:unauthorized`, `:код` | **Символ** — интернированная неизменяемая строка-идентификатор. `failure(:unauthorized, 'provider.invalid_credentials')` — первый аргумент символ (HTTP-статус как имя), второй строка (код). | `const` enum-значение / iota-подобный идентификатор |
| `def check_conditions(operation, request_method) … end` | Метод. Последнее вычисленное выражение — возвращаемое значение, `return` нужен только для раннего выхода. | `func (s *Service) CheckConditions(op, rm) Result` |
| `return failure(…) if operation.amount < MIN_AMOUNT` | Модификатор `if` после выражения: «сделай X, если Y». Читается как guard clause. | `if op.Amount < min { return failure(…) }` |
| `unless` | `if not`. | `if !cond` |
| `super` | Вызвать одноимённый метод родителя с теми же аргументами (`check_conditions` сначала делает базовые проверки контракта). | вызов метода встроенной структуры `s.BaseService.CheckConditions(...)` |
| `rescue Provider::RateLimitError => e` | Блок обработки исключений в конце метода; `=> e` кладёт исключение в переменную. Несколько `rescue` — по типам. | `if errors.As(err, &rateLimit)` — но исключения, а не возвращаемые ошибки |
| `raise Provider::SignatureError, "…"` | Бросить исключение. | `panic` по механике, `return err` по смыслу; в сервисе они ловятся `rescue` и превращаются в `failure` |
| `failed?`, `verify_signature!` | Соглашения об именах: `?` — метод возвращает true/false; `!` — метод «опасный»: бросает исключение или меняет объект. | `IsFailed()`; `MustVerify()` |
| `"#{BASE_URL}/payouts"` | Интерполяция строки. | `fmt.Sprintf("%s/payouts", baseURL)` |
| `client.post(url, json: payload, headers: …)` | Именованные аргументы (keyword args). `json:` — ключ, не JSON-литерал. | опции-структура `PostOpts{JSON: payload, Headers: h}` |
| `def process_callback(payload, raw_body: nil, headers: {})` | Keyword-аргументы со значениями по умолчанию: вызов `process_callback(payload)` из ТЗ остаётся валидным. | функциональные опции / необязательные поля структуры |
| `ENV.fetch('NOVAPAY_BASE_URL', default)` | Переменная окружения с дефолтом. `fetch` без дефолта бросает исключение, если ключа нет — это намеренно для `credentials.fetch('api_key')`: отсутствие секрета должно быть громким. | `os.Getenv` + проверка; `fetch` без дефолта ≈ «must» |
| `hash['status']`, `hash.dig('error', 'code')` | Доступ по ключу; `dig` — безопасный вложенный доступ, `nil` вместо паники, если промежуточного ключа нет. | `m["status"]`; `dig` ≈ цепочка проверок `ok` |
| `nil` | Отсутствие значения. | `nil` |
| `.compact`, `deep_compact` | `compact` убирает `nil` из массива/хеша. Наш `deep_compact` — рекурсивно, чтобы необязательные поля без значения не улетали как `null`. | фильтрация map перед `json.Marshal`; ≈ `omitempty` |
| `{ \|v\| … }` / `do … end` | Блок — анонимная функция, передаваемая методу (`transform_values { \|v\| … }`, `each { … }`). | замыкание `func(v) {…}` в аргументе |
| `value.map { … }`, `.reject { … }`, `.select { … }` | Функциональная обработка коллекций. | цикл `for` с фильтром |
| `case value when Hash then … when Array then … else … end` | Ветвление по типу или значению. | `switch v := value.(type)` |
| `Struct.new(:id, :amount, …, keyword_init: true)` | Быстрое объявление класса-записи с полями (`Provider::Operation`). | `type Operation struct{ ID; Amount; … }` |
| `Data.define(:name, :credentials, :config)` | Неизменяемая запись (Ruby 3.2+). На них весь IR: после создания поля не меняются. | struct без сеттеров, все поля «read-only» |
| `alias_method :provider_operation_id, :provider_operation_key` | Второе имя для того же метода (имя из ТЗ и имя с платформы по QA 2). | метод-обёртка `func (o) ProviderOperationID() { return o.ProviderOperationKey }` |
| `OpenSSL::HMAC.hexdigest('SHA256', secret, body)` | HMAC из stdlib, результат в hex. | `hmac.New(sha256.New, key)` + `hex.EncodeToString` |
| `secure_compare` | Сравнение строк за постоянное время (защита от timing-атак на подпись). | `hmac.Equal` |
| `JSON.generate(payload)` / `JSON.parse(body)` | Сериализация stdlib. | `json.Marshal` / `json.Unmarshal` |
| `format('%.2f', amount)` | Форматирование числа (сумма строкой в рублях у CardPay). | `fmt.Sprintf("%.2f", x)` |
| `(amount * 100).round.to_i` | Перевод в копейки: умножить, округлить, привести к целому. | `int64(math.Round(x * 100))` |
| `private` | Всё ниже этой строки — приватные методы класса. | имя с маленькой буквы |
| `require 'x'` / `require_relative` | Подключить файл/гем. | `import` |
| `Open3.capture2e` | Запустить внешнюю команду и забрать вывод (`bin/demo`, `Verifier` запускает `ruby -c` и `rspec`). | `exec.Command(...).CombinedOutput()` |
| `Provider::` / `Forge::` | `::` — разделитель пространств имён. `Forge::SpecError` — класс `SpecError` внутри модуля `Forge`. | `forge.SpecError` |
| `#method` в документации | Запись `Analyzers::Fields#unresolved_ref` означает метод экземпляра; `.method` — метод класса (`Rules.load`). | метод на значении vs функция пакета |

### Построчно: `create_request` — на случай, если попросят объяснить код

```ruby
def create_request(operation, request_method = 'create')          # аргумент по умолчанию — 'create'
  return fetch_status(operation) if STATUS_METHODS.include?(request_method)   # 'status'/'check' → делегируем
  requisite_type = requisite_type_for(operation, request_method)   # 'sbp' | 'card' | nil
  return failure(:unprocessable_entity, 'requisite_missing') unless requisite_type
  payload = build_payout_payload(operation, requisite_type)        # хеш → JSON-тело, nil-поля вычищены
  response = client.post("#{BASE_URL}/payouts", json: payload,     # HttpClient; 401/429/5xx → исключения
                         headers: auth_headers.merge(idempotency_headers(operation)))
  parse_create_response(operation, response)                       # 201/409 → id + статус; иначе failure
rescue Provider::RateLimitError => e                               # 429 → retry_after наружу
  failure(:too_many_requests, 'provider.rate_limit', retry_after: e.retry_after)
rescue Provider::UnauthorizedError                                 # 401
  failure(:unauthorized, 'provider.invalid_credentials')
rescue Provider::ServerError, Provider::ConnectionError => e       # 5xx, таймаут, DNS
  failure(:bad_gateway, 'provider.unavailable', message: e.message)
end
```

Фраза для эксперта: «Метод делает четыре вещи: делегирование служебных `request_method`, выбор
типа реквизита, отправка через наш HttpClient и классификация ответа; все сетевые и auth-ошибки
ловятся `rescue` и возвращаются как `failure` с кодом `provider.*`, воркер платформы не падает.»

### Три вещи, которые Go-инженеру легко перепутать

1. **Исключения vs результат.** В Go ошибка — возвращаемое значение. В нашем сервисе внешние сбои —
   исключения из `HttpClient`, но наружу они **никогда** не выходят: каждый метод контракта заканчивается
   `rescue` и возвращает `Result` (`success`/`failure`). Это и есть требование «обрабатывает ошибки».
2. **Символ vs строка.** `:unauthorized` — символ, имя HTTP-статуса для `failure`; `'provider.invalid_credentials'` —
   строка, код ошибки для платформы. Оба видны в тестах сгенерированного spec.
3. **`spec` — это тесты.** «Спека» в разговоре — OpenAPI-файл; `*_spec.rb` — RSpec-тесты. На демо говорить
   «спецификация» про OpenAPI и «RSpec» про тесты, чтобы эксперты не путались.
