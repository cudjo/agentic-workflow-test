# Integration-05 — WORKFLOW_LOG (append-only)

## 2026-10-19 — Integration-05 выполнен (tasker, devops/backend)

- **Задача:** закоммитить Fix-4a в его worktree и свести Fix-4a + Fix-4b в `v2` через cherry-pick, затем верифицировать сборку/тесты/smoke.
- **Skills:** загружен `godot` — домен задачи: GDScript 4.x, интеграция сцен/autoload (`SceneRouter`, `GameState`), headless GUT и `--import`. Другие skills не требовались (нет БД/сети/React/Python/Go/Docker). Загрузка по домену, а не по факту наличия `.gd`-файлов.

### Состояние до интеграции (инспекция)

- `v2` HEAD = `39ab884`; Fix-4b = `d34169d` (detached от `39ab884`); Fix-4a = uncommitted в worktree `...\worktree\1ee15a\fix4a` (detached `39ab884`).
- Fix-4a worktree: 6 modified + 2 untracked (`test_fix4a_flow.gd` + `.uid`), чужих untracked нет.
- Основная директория: только чужие `docs/WORKFLOW_LOG.md` (modified) и QA-артефакты `game/tests/e2e/*` (untracked) — в коммиты не включались.

### Выполнено

1. Fix-4a закоммичен в worktree `1ee15a\fix4a`: **`2814841`** (8 файлов, +718/−19; только файлы фикса + новый тест).
2. В `v2`: `git cherry-pick 2814841` → **`19cf35b`**; `git cherry-pick d34169d` → **`9a7513f`**. Конфликтов не было, рабочее дерево не пересекалось с фиксами.
3. Сверка деревьев: `git diff 2814841 19cf35b` и `git diff d34169d 9a7513f` — пусто (перенос без потерь).

### Верификация (portable Godot 4.7.2.stable, из `game/`)

- `--headless --import` → exit 0.
- GUT `-gdir=res://tests -ginclude_subdirs -gexit` → **528/528 passed**, 47 scripts, 7154 asserts, 135.951s, exit 0 (518 базовых + 5 Fix-4a + 5 Fix-4b).
- Smoke `--headless --path game --quit-after 240` → exit 0, SCRIPT ERROR: 0.
- `GODOT_PATH` в окружении не задан; использован portable `Godot_v4.7.2-stable_win64_console.exe` (winget package).

### Ограничения

- Код/тесты не правились, `docs/TASKS.json` не тронут, untracked `game/tests/_probe.gd` и `opencode.jsonc` не тронуты, worktree'ы не удалялись.
- Smoke — не замена независимой приёмке QA и ревью Guardian.

## 2026-10-19 - Release-сборка для ручного тестирования (tasker-devops)

- **Skills:** загружен `godot` (headless import/export, проверка PCK, smoke экспортированного бинарника). Других skills не требовалось (нет UI/БД/сетевых изменений).
- **Задача:** собрать release-билды Windows/Linux из `v2` HEAD `00eae32` по готовым пресетам T-02, без изменения кода/тестов/пресетов/`docs/TASKS.json`.
- **Окружение:** portable `Godot_v4.4.1-stable_win64_console.exe` (`4.4.1.stable.official.49a5bc7b6`, `%TEMP%\opencode\godot\`); шаблоны `%APPDATA%\Godot\export_templates\4.4.1.stable\` (`windows_release_x86_64.exe`, `linux_release.x86_64`). `GODOT_PATH` в среде не задан — бинарник передан явным путём.
- **Импорт:** `godot --headless --path game --import` → exit 0, SCRIPT ERROR/parse-ошибок нет.
- **Экспорт:** `--export-release "Windows Desktop"` → exit 0; `--export-release "Linux"` → exit 0 (оба — release, `embed_pck=true`).
- **Артефакты:** `game/build/windows/AshenBastion.exe` — 98 896 896 B (94,3 MB), magic `MZ`; `game/build/linux/AshenBastion.x86_64` — 71 064 784 B (67,8 MB), magic `7F 45 4C 46`. SHA-256 exe: см. отчёт Tasker.
- **Состав PCK (разбор таблицы):** 539 записей; `tests/` и `addons/gut` — **0** записей (исключены корректно); главная сцена `MainMenu.scn` и `ui/menus/MainMenu.tscn` присутствуют. Строки `res://tests/...` в бинарнике — только содержимое `.godot/uid_cache.bin`/`global_script_class_cache.cfg` (метаданные сканера), самих тестов в паке нет.
- **Smoke:** `AshenBastion.exe --headless --quit` → exit 0, SCRIPT ERROR 0, ERROR 0. Оконный запуск `--quit-after 180` → окно открылось (OpenGL Compatibility, NVIDIA), exit 0; Movie Maker (`--write-movie ... --quit-after 30`) отрендерил 30 кадров главного меню (RU: «ПЕПЕЛЬНЫЙ БАСТИОН», «Продолжить/Новая игра/Загрузить/Настройки/Выход») — `%TEMP%\opencode\ab_movie\frame00000015.png`.
- **Найденный дефект (pre-existing, в рамках ограничений не правился):** в экспорте `data/factions/*.tres` упакованы как `*.tres.remap`; `FactionManager._load_factions()` перебирает `DirAccess.get_files()` и фильтрует `file_name.ends_with(".tres")` → загружено 0 из 3. В editor/`--path game` warning отсутствует, т.е. проблема только у экспортированного билда. Следствие для ручного теста: репутация, доступ к торговцу/территории, фракционные квесты и концовка в билде не работают. Рекомендация: явный список путей фракций (`preload`/массив) или учёт `.tres.remap` при переборе; это отдельная fix-задача.
- **Ограничения:** `game/build/` не коммитился (в `game/.gitignore`); код, тесты, `export_presets.cfg`, `docs/TASKS.json` не менялись; untracked `game/tests/_probe.gd`, `opencode.jsonc`, `game/tests/e2e/` не трогались. Этот лог — единственная правка. Smoke не заменяет приёмку QA и ревью Guardian.
