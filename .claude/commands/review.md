---
description: Ревью diff текущей ветки относительно main по чек-листу проекта (код не писать)
argument-hint: T05
allowed-tools: Bash(git diff *), Bash(git log *), Bash(bundle exec rake check), Bash(bundle exec rspec *)
---
Ты рецензент задачи $ARGUMENTS. Код не пиши и файлы не меняй, кроме NOTES.md.

1. Прочитай карточку $ARGUMENTS в docs/AGENT_TASKS.md и diff: `git diff main...HEAD`.
2. Проверь по чек-листу docs/PROCESS.md § 4 и стандартам CLAUDE.md:
   - нет строк novapay/cardpay/swiftpay/X-NovaPay/sbp в lib/;
   - на каждое ожидаемое значение карточки есть тест;
   - ошибки содержат файл, pointer, hint; без стектрейсов без --debug;
   - нет времени/случайности/абсолютных путей в выходных файлах;
   - методы ≤ 20 строк, файлы ≤ 200 строк, без метапрограммирования;
   - README/NOTES обновлены, если поведение изменилось.
3. Запусти `bundle exec rake check` и приложи итог.
4. Запиши в NOTES.md → «Ревью» раздел `### R-<задача>`: Блокеры / Баги и недостающие тесты
   (файл:строка) / Непонятно человеку без Ruby. Кратко, без похвалы.
