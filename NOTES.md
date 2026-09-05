# NOTES — решения и обратная связь

Зачем читать: здесь фиксируются архитектурные решения (ADR-lite) и дословная обратная связь экспертов с
чек-поинтов. Агент обязан читать раздел «Решения» перед задачей, если карточка ссылается на D-xx,
и добавлять запись, если принимает новое решение.

## Решения

### D-01 · Правила и словари вместо LLM
Контекст: нейросети внутри продукта запрещены; классификация эндпоинтов/статусов/полей всё равно нужна.
Решение: подсчёт очков по словарям `rules/*.yml` + `Finding(confidence)`; пороги 0.8/0.5.
Альтернативы: жёсткие regex без confidence (не объяснимо); эвристики в коде (не расширяемо).
Следствия: детерминизм, аудируемость, расширение без Ruby; неоднозначное — WARN + overrides.

### D-02 · `request_method` — логический тип действия
Контекст: письменный ответ организаторов. Решение: `'status'`/`'check'` → `fetch_status`; тип реквизитов из
enum спеки → выбор варианта payload; иначе первый ключ `payout_requisite`. HTTP-verb всегда из спеки.
Следствия: `REQUISITE_TYPES`, `STATUS_METHODS`, `requisite_type_for` в каждом сервисе.

### D-03 · `process_callback(payload, raw_body: nil, headers: {})`
Контекст: подпись считается от сырого тела (канон NovaPay), а ТЗ показывает `process_callback(payload)`.
Решение: kwargs с default — вызов из ТЗ остаётся валидным; без `raw_body` подписываем `JSON.generate(payload)`
(с комментарием о риске канонизации). Альтернативы: зарезервированные ключи `_raw_body` в payload (неявно).

### D-04 · Доп. эндпоинты — хелперы вне контракта
Контекст: QA 1 — cancel/balance в контракт не входят. Решение: генерируем `cancel_request`, `fetch_balance`
под комментарием «Outside BaseService contract», `INFO outside_contract` в отчёте, раздел «Вне контракта» в INTEGRATION.md.

### D-05 · Внешний `$ref`: критичность решает анализатор, а не загрузчик
Контекст: Load не знает ролей эндпоинтов. Решение: `RefResolver` помечает место `x-forge-unresolved`,
`IR::Schema#unresolved_ref`; `Analyzers::Fields` бросает `UnsupportedError` (exit 1), если пометка в запросе
create; иначе `Warning(:unsupported, 'external_ref')` и схема `{}`.

### D-06 · Канон предупреждений NovaPay — 6 (3 WARN, 3 INFO)
Контекст: тесты T06/T08 фиксируют число. Решение: список в `docs/SPEC_ANALYSIS_NOVAPAY.md`. Менять — только
через правку документа и golden с записью здесь.

### D-07 · Третья спека — payout на банковский счёт (SwiftPay), не pay-in
Контекст: QA 1 — только выплаты. Решение: SwiftPay = OpenAPI 3.1 JSON, basic, IBAN, oneOf, top-level webhooks.
Pay-in — только в «Что дальше».

### D-08 · `--include-paths` для больших спек
Контекст: Stripe — 419 путей, десятки кандидатов на create. Решение: glob-фильтр путей в CLI и `paths.include`
в overrides; при конфликте ролей отчёт подсказывает этот флаг.

### D-09 · `method_delete` — сигнал отмены в словаре ролей
Контекст: SwiftPay отменяет выплату через `DELETE /v1/payments/outbound/{id}` без слова cancel в пути; по
исходным весам роль набирала 0.65 и давала `WARN low_confidence`, хотя REST-семантика однозначна.
Решение: сигнал `method_delete: 0.20` в `roles.cancel` (`rules/endpoint_roles.yml`) → 0.85 без WARN.
Альтернативы: оставить WARN и закрывать через overrides (лишний шум для типового REST).
Следствия: любой DELETE на ресурсе с path-параметром — кандидат в cancel; конфликт с другими ролями невозможен
(status/create требуют GET/POST).

### D-10 · Спековые предупреждения живут в `Analyzers::Runner`
Контекст: `production_default`, `outside_contract`, `no_cancel_endpoint` не относятся ни к одному анализатору,
а зависят от ролей и `servers`. Решение: Runner добавляет их к Finding `endpoint_roles` после прогона всех
анализаторов; число findings остаётся 7. Альтернативы: отдельный анализатор `Servers` (лишняя сущность ради
одного WARN). Следствия: `Runner.run(spec).values.flat_map(&:warnings)` — единственный источник полного списка.

### D-13 · Сгенерированный spec сравнивает тело запроса как подмножество примера
Контекст: точное равенство тела ломается, когда поле не отображено (TODO → nil) или его `source` задан
пользователем в overrides (значение не выводится из примера спеки). Решение: `subset_of?(sent, example)` —
каждое отправленное не-nil значение обязано совпасть с примером; поля с override `source` исключаются
из сравнения; недостающие канонические реквизиты типа (CONTRACT § 3) добираются из
`rules/field_aliases.yml → requisite_defaults`, чтобы пользовательские выражения имели данные.
Альтернативы: не проверять тело вовсе (теряем главную гарантию), точное равенство (ложные падения).
Следствия: тест не ловит *пропущенное* обязательное поле — это закрывает проверка провайдера/мок (T15).

### D-14 · Циклический и битый `$ref` — маркер, а не падение загрузчика
Контекст: реальные спеки содержат рекурсивные схемы (Stripe `file ↔ file_link`, Square `CatalogObject`) и
ссылки на отсутствующие схемы (Square `AppFeeAllocation`) вне контракта выплат; падать на них — значит не
проанализировать провайдера вовсе. Решение: `RefResolver` обрывает цикл маркером
`x-forge-circular: "A -> B -> A"` и помечает отсутствующую цель `x-forge-unresolved`; `Analyzers::Fields`
бросает `SpecError` (exit 1), только если маркер в схеме запроса create (как внешний `$ref`, D-05).
Резолвер мемоизирует цели по `$ref`: Stripe (8 МБ, тысячи ссылок) грузится за 0.1 с вместо минут.
Следствия: `spec/fixtures/broken/{cyclic_ref,bad_ref}.yaml` по-прежнему дают exit 1 — решение принимает
анализатор, а `Loader.load` их не отвергает.

### D-15 · Хелперы вне контракта — отдельный класс `<Provider>Extras`
Контекст: обратная связь экспертов — сервис должен содержать только контракт, хелперы добавлять «через другие
классы». Решение: `cancel_request`/`fetch_balance` рендерятся в `<provider>_extras.rb` как
`Provider::<Provider>Extras < <Provider>Service` (наследует client, auth_headers, apply_status); файл не
создаётся, если таких эндпоинтов нет. Сервис — ровно четыре метода контракта.
Следствия: `docs/OUTPUT_FORMAT.md` § 1 (golden-цель) отличается — секция «Outside BaseService contract»
заменена комментарием-ссылкой; golden обновлены; в сгенерированном spec cancel тестируется через Extras.

### D-16 · `--strict` — комбинированный режим
Контекст: эксперты хотят строгий режим, но «программа не должна завершать работу». Решение: `--strict`
делает всё (генерация, верификация, report.txt, полный вывод) и лишь в конце возвращает exit 4 при
WARN/UNSUPPORTED; строка `Done:` явно это сообщает. По умолчанию exit 0 — команда ТЗ `bin/integrate` не
краснеет на допущениях.

### D-17 · `fields.<path>.variant` — выбор варианта oneOf/anyOf
Overrides передаются в `Analyzers::Runner` (только ключи, влияющие на обход: `fields.*.variant`);
`FieldWalker` берёт вариант по `x-forge-ref-name`, WARN `one_of_first_variant` не выдаётся; несуществующее имя →
WARN `variant_not_found` + первый вариант. SwiftPay с overrides — 0 WARN.

### D-18 · Form-urlencoded тела
`OperationPlan#body_encoding = 'form'`, когда у запроса create нет JSON media type, но есть
`application/x-www-form-urlencoded`; сервис шлёт `form: payload`, `HttpClient` кодирует вложенные ключи как
`parent[child]` (Stripe-стиль); WARN `media_type_form`. Сгенерированный spec парсит form-тело и сравнивает
значения как строки.

### D-19 · Статус через POST с id в теле
Сигнал `id_body_field` (0.30) + `method_post_with_id_body` (0.10) в `roles.status`; `OperationPlan#status_request_field`
— имя поля (`*_id`/`id`); шаблоны сервиса, spec и мока переключаются на `POST` с телом `{field => provider_operation_id}`.
Plaid: `POST /transfer/get` → status 0.80.

### D-20 · Валидация фикстур по IR-схеме без нового гема
`Fixtures::Validator` проверяет типы, `required`, `enum` примеров запроса/ответов/webhook по схемам той же спеки;
расхождение → `INFO fixture_schema_mismatch` (пример берётся как есть). На NovaPay найдено настоящее расхождение
в ТЗ: пример 401 `error.code: unauthorized` не входит в enum `PayoutError.code`. Уровень INFO, чтобы канон
«3 WARN + 3 INFO» остался; json_schemer не добавлен (новый гем — только с согласия).

### D-21 · Живые провайдеры без ключей — проверка транспорта и классификации ошибок
Сгенерированные из реальных спек сервисы вызывали настоящие sandbox Stripe/Paystack/PayPal с неверным ключом:
401 → `provider.invalid_credentials`, таймаут → `provider.unavailable`. Найдены и закрыты два дефекта:
`generate` падал на спеке без enum статусов (пустой `STATUS_MAP` → TODO), `create_request` падал KeyError при
чужом типе реквизитов (теперь `requisite_missing`, как в `check_conditions`). Таблица — `docs/AUDIT.md` § 5a.

### D-22 · Проверка на реальных спеках закрывает 10 дефектов генерации (5.09)
Все шесть реальных спек с create теперь проходят `generate` с зелёным сгенерированным spec; список дефектов и
исправлений — `docs/AUDIT.md` § 5a. Принципиальные решения: успешный create без распознанного статуса →
`in_progress` (итог придёт через fetch_status/webhook), строгий `unknown_provider_status` — только в
`fetch_status`; тело запроса в сгенерированном spec сверяется по общим с примером ключам; apiKey в query
добавляется хелпером `with_auth(url)`.

### D-23 · Веб-интерфейс — тонкая обёртка над CLI, только для демо
Организаторы: «CLI достаточно». Веб-слой (`lib/forge/web`, Sinatra + Puma из Gemfile, без новых гемов и без БД)
вызывает те же `GenerateCommand`/`Verifier`, что и `bin/forge`; прогоны — каталоги на диске (`FORGE_WORKDIR`).
Деплой: Dockerfile-таргет `web`, `docker compose up`. Ограничения безопасности: примеры только из `examples/`,
id прогона — `[\w-]+`, размер спеки ≤ 20 МБ, секретов в артефактах нет. Логика анализа в веб-слой не попадает
(правило «шаблоны и парсер не знают друг о друге» сохраняется: UI знает только команду).

## Реальные спеки (T18 записывает сюда падения и странности)

Прогон 4.09 (`rake real`): 7/7 спек — exit 0, снапшоты в `examples/real/reports/`. Что вскрылось и что сделано:

| Спека | Проблема | Решение |
|---|---|---|
| Stripe, Square | рекурсивные схемы (`file ↔ file_link`, `CatalogObject`) — резолвер падал с `circular $ref` | D-14: маркер `x-forge-circular`, фатально только в схеме запроса create |
| Stripe | 8 МБ, тысячи ссылок на одни схемы — резолв и IR росли экспоненциально (> 10 мин) | кэш целей `$ref` + мемоизация `Schema.from` по identity → 0.1 с |
| Square | `$ref` на несуществующую схему `AppFeeAllocation` вне контракта | D-14: `x-forge-unresolved`, UNSUPPORTED вне create |
| Paystack | `$ref` на path-pointer с percent-encoding `%7Bid%7D` | `URI.decode_www_form_component` при lookup |
| Paystack | повтор `--include-paths` терял первое значение (Thor array) | `repeatable: true` + flatten |
| Plaid | при равных очках create выигрывал `/transfer/originator/funding_account/create` | tie-break: короче путь → каноничнее ресурс |
| Plaid | статус через `POST /transfer/get` с id в теле | не поддержано (README «Ограничения», roadmap) |
| Paystack | `DELETE /transferrecipient/{code}` принят как cancel (0.55, WARN) | честный WARN + hint `endpoints.<id>: other` |

## CP1 · пт 4.09

(дословно замечания экспертов → «что меняем»)

## CP2 · сб 5.09

## CP3 · вс 6.09

## Ревью

Самопроверка по чек-листу PROCESS § 4 (4.09, после T20):
1. `rake guard:vendor` — чисто; единственные упоминания провайдеров — `spec/`, `examples/`, `docs/`.
2. Каждое значение из карточек T01–T20 покрыто тестом (216 примеров, покрытие 97.8 % / 84.6 %, минимум по файлу 83 %).
3. Ошибки: `error: <что> at <pointer> in <file>\n  hint: <что делать>`, без стектрейса без `--debug` (`spec/cli_spec.rb`).
4. Детерминизм: `rake determinism` (21 файл, два прогона), в `report.txt` пути относительно каталога вывода.
5. Размеры: `plan/fixtures.rb` был 227 строк → вынесена `FixturesOperation`; ERB-шаблоны > 200 строк (service, spec) —
   это выходной код, а не логика.
6. README/NOTES обновлялись в каждой карточке; решения D-01…D-14.
7. Отклонения от docs, о которых знать эксперту: `Analyzers::Fields` решает критичность `$ref` (D-05/D-14);
   `OperationPlan#endpoint` (D-11); тело запроса в сгенерированном spec — подмножество примера (D-13);
   `reference_spec` проверяет `payout_requisite` + `'sbp'`/`'phone'`, а не буквальный `dig('sbp', 'phone')` из ТЗ,
   потому что golden из OUTPUT_FORMAT § 1 использует `build_recipient` с вариантами по типу.
Блокеров нет.

(отчёты `/review` по задачам: `### R-T05`)
