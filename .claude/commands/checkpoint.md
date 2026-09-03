---
description: Подготовить демо к чек-поинту N (сценарий из docs/PLAN.md), проверить в чистом клоне
argument-hint: 2
allowed-tools: Bash(git *), Bash(bundle *), Bash(bin/*), Bash(rake *)
---
Подготовь демонстрацию для чек-поинта $ARGUMENTS.

1. Возьми сценарий из docs/PLAN.md → «Что показываем на чек-поинтах» для CP$ARGUMENTS.
2. Сделай чистый клон в tmp/cp-clone (`git clone . tmp/cp-clone`), выполни там `bundle install`
   и каждую команду сценария. Запиши точный вывод в docs/DEMO_CP$ARGUMENTS.md. Отметь, что не работает.
3. Составь 5 тезисов для рассказа (пайплайн; правила и словари вместо LLM; Finding + confidence;
   overrides как механизм, рекомендованный организаторами; что дальше) и 3 вопроса экспертам.
4. Предложи, что из cut-list docs/PLAN.md резать, если что-то не работает.
