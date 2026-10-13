# Project: «Пепельный Бастион» — пиксельная метроидвания в стиле Gothic (Godot)

## Статус
- **Гейт 1 (Требования):** ✅ Пройден
- **Гейт 2 (Макет):** ✅ Пройден
- **Гейт 3 (Merge):** ⬜ Ожидает
- **Гейт 4 (Deploy):** ⬜ Ожидает

## Артефакты
- [docs/TICKET.md](TICKET.md) — Триаж вводной
- [docs/SPEC.md](SPEC.md) — Требования (утверждены, гейт 1)
- [docs/DESIGN.md](DESIGN.md) — Дизайн (утверждён, гейт 2)
- [docs/PLAN.md](PLAN.md) — План реализации и архитектура Godot-проекта
- [docs/TASKS.json](TASKS.json) — Декомпозиция задач (T-01…T-37)
- [docs/init.sh](init.sh) / [docs/init.ps1](init.ps1) — Скрипты инициализации окружения
- [docs/QA.md](QA.md) — Отчёт QA (ожидает)
- [docs/REVIEW.md](REVIEW.md) — Ревью (ожидает)
- [docs/WORKFLOW_LOG.md](WORKFLOW_LOG.md) — Журнал действий
- [docs/mockups/](mockups/index.html) — HTML-макеты (6 экранов + index)

## Стек
- **Движок:** Godot 4.4+ (GDScript), проект в `game/`
- **Стек-скилл:** `godot` (добавлен Planner'ом в `~/.config/opencode/skills/godot/`)
- **Разрешение:** 480×270, целочисленное масштабирование, nearest-фильтр
- **Платформы:** ПК (Windows Desktop, Linux)

## Быстрый старт
```bash
# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File docs/init.ps1

# Linux/macOS/Git Bash
bash docs/init.sh
```
Скрипты идемпотентны, проверяют наличие Godot и (при готовом `game/project.godot`) импортируют ресурсы и прогоняют тесты.
