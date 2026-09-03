# План реализации forge (пт 4.09 → вс 6.09.2026)

Время — Алматы (ALA = MSK+2). Чек-поинты с экспертами: 15:00–18:00 ALA ежедневно (слот назначает
модератор). Стоп-код: воскресенье 01:00 ALA (23:00 MSK); **наш внутренний freeze — вс 22:00 ALA**,
последний пуш не позднее 00:00 ALA. Полный контекст сроков — `docs/HACKATHON_PLAN.md`.

## Принципы плана

1. **Сквозной путь раньше ширины.** Сначала `novapay.yaml → 6 файлов → зелёный сгенерированный spec`,
   потом вторая и третья спеки, потом реальные провайдеры.
2. **Каждый этап заканчивается демонстрируемым состоянием** — тем, что можно показать на чек-поинте
   одной командой. Полуготовое не считается.
3. **Оценивают код в репозитории** (QA 1). Значит, читаемость, тесты, README и понятные ошибки —
   не «полировка в конце», а часть каждой задачи.
4. **Критерии → задачи.** У каждой карточки в `docs/AGENT_TASKS.md` указано, какие баллы она закрывает.
   Порядок задач = порядок убывания «баллы за час».

## Этапы (milestones)

| Этап | Результат (DoD) | Задачи | Дедлайн ALA | Баллы (эксп./жюри) |
|---|---|---|---|---|
| **M0 Foundation** | Репозиторий, Gemfile, rubocop/rspec/SimpleCov зелёные, Docker собирается, CI-скелет, docs/ на месте | T01 | пт 11:00 | база для всего |
| **M1 Analyze** | `bin/forge analyze novapay.yaml` печатает отчёт ТЗ: 5 ролей, auth, статусы, ошибки, webhook, сумма, 3 WARN + 3 INFO; битые спеки → exit 1 с подсказкой | T02–T07 | пт 15:00 (**CP1**) | разбор спеки 20/20 |
| **M2 Generate NovaPay** | `bin/forge generate` → 5 файлов (без мока), `ruby -c` ok, `spec/reference_spec.rb` + golden зелёные, сгенерированный spec зелёный, `bin/integrate` как в ТЗ | T08–T12 | сб 03:00 | генерация 25/25, преобразование 15/15, документация 13, удобство 15/10 |
| **M3 Universal** | CardPay и SwiftPay генерируются; WARN/UNSUPPORTED совпадают с `docs/TEST_SPECS.md`; overrides закрывают WARN; реальные спеки: `analyze` не падает, отчёты сохранены | T13, T14, T18 | сб 15:00 (**CP2**) | универсальность 15/10 |
| **M4 Proof** | Мок-сервер из спеки, `bin/e2e`: create → webhook → approved; покрытие ≥ 90 % | T15, T19 | сб 24:00 | доп. идеи 6, «отправка запросов» 5 |
| **M5 Ship** | README для жюри, Docker с нуля, CI полностью зелёный, rubocop 0, тег `v1.0.0`, демо-скрипт и бэкап-скринкаст | T16, T17, T20, T21 | вс 15:00 (**CP3**) → 22:00 freeze | удобство/качество 25/20, полнота 8 |

## Расписание по часам

### Пятница 4.09

| Время ALA | Что | Кто |
|---|---|---|
| 09:00–11:00 | T01 каркас (если не закрыт в четверг — закрыть первым делом). Положить `docs/`, `CLAUDE.md`, `spec/reference/`, `examples/` из этого комплекта. Первый зелёный `rake check`. | Core |
| 11:00–13:30 | T02 Loader/RefResolver ∥ T03 IR/Builder (два worktree) | Core ∥ Core-2 |
| 13:30–15:00 | T04 EndpointRoles → T05 Auth/Statuses/Errors ∥ T06 Webhooks/Amount/Fields (T05 и T06 параллельно после T04) | Analyzers ∥ Analyzers-2 |
| 15:00–16:00 | T07 `analyze` + Report. Прогон демо CP1 (скрипт ниже). | Core |
| **15:00–18:00** | **CP1.** Показать `analyze` на NovaPay и на битой спеке. Вопросы экспертам — см. ниже. Записать фидбэк в `NOTES.md`. | John |
| 18:00–21:00 | T08 Plan/Naming/Validations → T09 Overrides ∥ T10 Renderers::Base + Service + Verifier + заглушка контракта | Core ∥ Renderers |
| 21:00–01:00 | T11 IntegrationDoc, Fixtures (+Synthesizer), ServiceSpec | Renderers |
| 01:00–03:00 | T12 `generate`, `bin/integrate`, golden. **M2 закрыт.** Обновить README (статус). | Core |

### Суббота 5.09

| Время ALA | Что | Кто |
|---|---|---|
| 09:00–12:00 | T13 CardPay: спека, overrides, golden; чинить привязки к NovaPay в анализаторах/словарях | Analyzers |
| 09:00–12:00 | T18 реальные спеки: `rake real:fetch`, `rake real:analyze`, отчёты в `examples/real/reports/`, `spec/real_specs_spec.rb` (тег `:real`) — параллельно, свои файлы | QA |
| 12:00–15:00 | T14 SwiftPay (3.1 JSON, basic, oneOf/allOf, top-level webhooks, problem+json, внешний $ref, подпись с timestamp → UNSUPPORTED) | Analyzers |
| **15:00–18:00** | **CP2.** Показать один генератор на трёх спеках + `--strict` + overrides + отчёт по Stripe/Adyen. | John |
| 18:00–22:00 | T15 MockServer + `bin/forge mock` + `bin/e2e` | Renderers |
| 18:00–22:00 | T19 качество: покрытие ≥ 90 %, негативные тесты CLI, rubocop, `--format json` snapshot — параллельно | QA |
| 22:00–24:00 | T16 часть 1: Dockerfile финал, CI все job'ы, README черновик для жюри | Docs |

### Воскресенье 6.09

| Время ALA | Что | Кто |
|---|---|---|
| 09:00–12:00 | T16 часть 2: README (критерий → где смотреть, реальный вывод `analyze`), `docs/` вычитать; T21 ревью-проход агентом-рецензентом по чек-листу | Docs, Reviewer |
| 12:00–15:00 | T20 демо: `bin/demo` (Ruby), прогон с секундомером ×3, скринкаст-бэкап; репетиция ответа «что отделяет от 100?» | John |
| **15:00–18:00** | **CP3 (обязателен).** Полное демо. Записать замечания → T17. | John |
| 18:00–21:00 | T17 полировка только по замечаниям CP3 (багфиксы и текст, без новых фич) | Core |
| 21:00–22:00 | Финальный `rake ci` в чистом клоне + `docker build` + `docker run` с нуля. Тег `v1.0.0`. **Freeze 22:00.** | John |
| 22:00–00:00 | Только README-опечатки, если критично. Последний пуш ≤ 00:00 ALA. После — репозиторий не трогать. | John |

### Понедельник–вторник

Пн: отдых; 7 слайдов (`docs/PITCH.md` появится в T20); 22:00 ALA — топ-5.
Вт: три прогона демо; питч 19:00–21:00 ALA.

## Что показываем на чек-поинтах

**CP1 (пт):** `bin/forge analyze --spec examples/specs/novapay.yaml` (текст), `--format json | head`,
`bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml` (ошибка с pointer и hint, exit 1).
Рассказ: пайплайн, Finding + confidence, словари вместо нейросети, overrides как подтверждённый
организаторами механизм.

**CP2 (сб):** `bin/forge generate` на NovaPay → открыть `novapay_service.rb`, `INTEGRATION.md` (раздел
«Допущения»), `bundle exec rspec output/novapay/novapay_service_spec.rb`. Затем то же на CardPay без и с
overrides (`--strict` → exit 4 → exit 0). Затем `bin/forge analyze` на Adyen Transfers и Stripe
(с `--include-paths '/v1/payouts*'`). Спросить: «что отделяет от 100?».

**CP3 (вс):** полное демо `bin/demo`: generate → rspec → `bin/e2e` (мок + webhook + approved) → README.
Показать CI-бейдж и Docker-запуск.

## Вопросы экспертам

- CP1: устраивает ли формат отчёта; достаточно ли WARN/INFO или хотят строгий режим по умолчанию;
  нужен ли `--format json` жюри.
- CP2: как оценивают «универсальность» на практике — покажем ли реальные спеки в плюс; ок ли
  `cancel_request`/`fetch_balance` как хелперы вне контракта.
- CP3: формат сдачи (публичность репозитория), состав команды на защите, что отделяет от 100.

## Реестр рисков

| Риск | Вероятность | Удар | Мера |
|---|---|---|---|
| Ruby-новичок не может проверить корректность кода агента | высокая | средний | Тесты как спецификация (карточка задаёт ожидаемые значения); `rake check` как единственный критерий; агент-рецензент T21 |
| Golden-тесты «фиксируют баги» | средняя | средний | Golden обновляется только после просмотра диффа человеком; reference-тест независим от golden |
| Универсальность окажется фикцией (привязка к NovaPay в шаблонах) | средняя | высокий | T13/T14 чинят только анализаторы/словари, не шаблоны; grep `novapay` в `lib/` в CI |
| Реальные спеки ломают загрузчик (6 МБ Stripe, `~1` в pointer'ах, form-encoded) | высокая | средний | T18 запускается в субботу утром, падения → карточки; JSON вместо YAML для Stripe; лимит времени 2 ч |
| Мок/e2e съедают вечер субботы | средняя | низкий | Cut-list: e2e можно заменить скринкастом сгенерированного spec |
| Коммит после стоп-кода | низкая | фатальный | Freeze 22:00 ALA; будильник; после 00:00 ALA не открывать репозиторий |
| Слишком много WARN на реальных спеках выглядит как слабость | средняя | средний | В README: «WARN — это честность, а не сбой»; `--include-paths` и overrides показывают путь к 0 WARN |

## Cut-list (что режем, если отстаём; сверху вниз)

1. R-задачи (json_schemer, Postman-экспорт, Swagger 2 → 3) — не начинать.
2. SwiftPay (T14): если к сб 13:00 CardPay не зелёный — SwiftPay только как `analyze`, без golden.
3. Реальные спеки (T18): оставить отчёты `analyze` для 3 провайдеров, не гнаться за 6.
4. e2e (T15): оставить мок-сервер и ручной сценарий в README, без `bin/e2e`.
5. Покрытие: порог 90 % → 85 %, но не ниже (`spec_helper` — одна цифра).

Никогда не режем: reference-тест, golden NovaPay, `INTEGRATION.md` с допущениями, README с
запуском одной командой, понятные ошибки CLI.

## Скрипт демо CP1 (пока `bin/demo` не написан)

```
bundle exec rake check                                    # зелёные тесты и rubocop
bin/forge analyze --spec examples/specs/novapay.yaml      # отчёт как в ТЗ + WARN/INFO
bin/forge analyze --spec examples/specs/novapay.yaml --format json | head -40
bin/forge analyze --spec spec/fixtures/broken/cyclic_ref.yaml; echo "exit=$?"
```
