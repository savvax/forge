# Агенты: роли, владение файлами, волны, промпты

Один агент = одна карточка = один worktree. Параллельно работают только карточки с непересекающимся
владением файлами. Все агенты читают `CLAUDE.md` автоматически; остальное — по списку «Читать» в карточке.

## Владение файлами

| Роль | Владеет | Не трогает |
|---|---|---|
| Core | `lib/forge.rb`, `lib/forge/{errors,version,loader,ref_resolver,cli,report,verifier}.rb`, `lib/forge/ir/`, `lib/forge/plan/`, `bin/forge`, `bin/integrate`, `spec/{loader,ref_resolver,cli,report,golden,reference}_spec.rb`, `spec/ir/`, `spec/plan/` | `rules/`, `templates/`, `lib/provider/` |
| Analyzers | `rules/*.yml`, `lib/forge/rules.rb`, `lib/forge/analyzers/`, `spec/analyzers/`, `spec/rules/`, `examples/specs/{cardpay.yaml,swiftpay.json}`, `examples/overrides/*` | `templates/`, `lib/forge/plan/` (кроме согласованных полей IntegrationPlan) |
| Renderers | `templates/`, `lib/forge/renderers/`, `lib/forge/fixtures/`, `lib/provider/`, `lib/forge/generated_spec_helper.rb`, `bin/e2e`, `spec/renderers/`, `spec/provider/` | `lib/forge/analyzers/`, `rules/` |
| QA | `spec/fixtures/`, `spec/golden/` (только через `UPDATE_GOLDEN`), `spec/real_specs_spec.rb`, `spec/determinism_spec.rb`, `Rakefile` (задачи `real:*`, `determinism`, `licenses`, `guard:*`), `examples/real/reports/`, `.github/workflows/ci.yml` | `lib/` (кроме багфиксов, согласованных с человеком) |
| Docs | `README.md`, `docs/` (кроме `AGENT_TASKS.md`), `docs/PITCH.md`, тексты в `templates/integration.md.erb` (согласовав с Renderers) | `lib/`, `rules/` |
| Reviewer | ничего (только читает и пишет отчёт в `NOTES.md` → «Ревью») | всё |

Общий файл `lib/forge/plan/integration_plan.rb` — контракт между Analyzers и Renderers. Новые поля
добавляются только через карточку Core, с одновременным обновлением `docs/ARCHITECTURE.md`.

## Волны (что можно запускать параллельно)

```
Волна 0  T01                                   (один агент, 1 ч)
Волна 1  T02 ∥ T03                             (Core, Core-2)
Волна 2  T04 → (T05 ∥ T06) → T07               (Analyzers, Analyzers-2, затем Core)
Волна 3  T08 → (T09 ∥ T10) → T11 → T12         (Core; Analyzers ∥ Renderers; Renderers; Core)
Волна 4  T13 ∥ T18  → T14                      (Analyzers ∥ QA; затем Analyzers)
Волна 5  T15 ∥ T19 ∥ T16(ч.1)                  (Renderers ∥ QA ∥ Docs)
Волна 6  T16(ч.2) ∥ T21 → T20 → CP3 → T17      (Docs ∥ Reviewer; John; Core)
```

Правило: агент не начинает карточку, пока её зависимости не в `main`. Если агент обнаружил, что нужен
чужой файл, — останавливается и пишет человеку, какое изменение нужно (не делает сам).

## Запуск агента

```
git checkout main && git pull
git worktree add ../forge-t05 -b t05-analyzers
cd ../forge-t05 && bundle install && claude
> /task T05
```

По завершении: в основном каталоге `git merge --no-ff t05-analyzers`, `bundle exec rake check`,
`git worktree remove ../forge-t05`.

## Шаблон промпта (то же, что делает `/task`)

```
Сделай задачу T05 из docs/AGENT_TASKS.md.
Контекст: CLAUDE.md уже загружен. Прочитай только разделы docs/, указанные в карточке.
Меняй только файлы из списка «Владеет». Если нужен чужой файл — остановись и спроси.
Порядок: тесты (красные) → реализация → bundle exec rake check зелёный.
Проверь, что bin/forge generate --spec examples/specs/novapay.yaml --out tmp/out --force не сломался
(если команда уже реализована).
Закончи: коммит `analyzers: auth, statuses, errors`; затем 5–7 предложений — что сделано, какие
решения принял и почему, что мне проверить руками, как объяснить это экспертам.
Если не помещаешься в сессию — остановись на зелёном состоянии и запиши остаток в карточку.
```

## Промпт рецензента (`/review`)

```
Ты рецензент. Код не пиши. Прочитай diff ветки относительно main (git diff main...HEAD) и карточку
задачи. Проверь по чек-листу из docs/PROCESS.md § 4 и по стандартам CLAUDE.md. Выпиши: (1) блокеры —
нарушения ограничений хакатона или контракта; (2) баги и недостающие тесты со ссылкой на файл:строку;
(3) что неясно человеку без Ruby-опыта. Кратко, без похвалы. Результат — в NOTES.md → «Ревью».
```

## Промпт для чек-поинта (`/checkpoint`)

```
Подготовь демонстрацию для чек-поинта N по docs/PLAN.md → «Что показываем». Проверь, что каждая
команда из сценария выполняется в чистом клоне (git clone в tmp/), запиши точный вывод в
docs/DEMO_CPN.md, отметь, что не работает. Составь 5 тезисов для рассказа (пайплайн, правила, без LLM,
overrides как рекомендованный механизм, что дальше) и 3 вопроса экспертам.
```

## Что агент обязан сказать человеку в конце

1. Что сделано (файлы, команды).
2. Какие решения приняты и почему (одно предложение на решение, со ссылкой на NOTES.md).
3. Что проверить руками (команда + ожидаемый вывод).
4. Что не сделано / остаток.
5. Как объяснить это экспертам за 2 минуты.
