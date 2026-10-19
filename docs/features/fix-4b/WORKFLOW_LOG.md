# Fix-4b — WORKFLOW_LOG (append-only)

## 2026-10-19 — Fix-4b выполнен (tasker-backend)

- **Источник:** Guardian request changes на `aece545`: **B-03** (EC-06 не работает для обычных врагов; флаг залипает после смерти на арене) и **MINOR-06** (i-frames не гасят knockback/flash). Контекст: SPEC EC-06, US-03/AC-03.1, AC-03.3; `docs/WORKFLOW_LOG.md` (строки 502–510).
- **Ограничение tasker:** Fix-4a (`core/death/`, `SceneRouter.gd`, `Main.gd`, `ui/menus/`, `ui/death/`) не трогался. `docs/TASKS.json`, untracked `game/tests/_probe.gd`, `opencode.jsonc` не менялись. Работа в чистом detached-worktree от `39ab884`.
- **Skills:** загружен `godot` — единственный профильный стек: типизированный GDScript, `Area2D`/`Hurtbox`/`Hitbox`, физика 60 Hz, autoload-состояние и headless GUT (CLI-флаги GUT/import). Другие skills не требовались: нет БД/сети/React/UI-стека. Причина фиксируется по домену задачи, а не по наличию GDScript-файлов.

### Что исправлено

**B-03 — producer `in_combat` от обычных врагов + сброс после смерти на арене**

- `autoload/GameState.gd`:
  - `in_combat` теперь складывается из ручного флага арены (`_in_combat_pinned`) и реестра источников-врагов (`_combat_sources`, ключ — `instance_id`).
  - Новый API: `set_combat_source(source, active)`, `is_combat_source_active(source)`, `reset_combat_state()`.
  - `set_in_combat(false)` — явное окончание боя: снимает ручной флаг и все источники (победа над боссом/выход из зоны/смерть), чтобы призванные/живые враги не держали запрет сохранения.
  - `_refresh_in_combat()` вычищает освобождённые источники; событие `EventBus.combat_state_changed` эмитится только при реальной смене значения.
- `entities/enemies/base/enemy.gd`:
  - Враг регистрирует себя источником боя при входе в `CHASE`/`ATTACK`/`HURT` и снимает при `PATROL`/`DEATH`, потере цели (`_lose_target`), смерти (`_die`) и `_exit_tree`.
  - Подписка на `EventBus.player_died` → враг теряет цель и выходит из боя; после респавна может снова агриться (новый источник).
  - Refcount «любой активный агрессор»: смерть/потеря цели одного врага не снимает `in_combat`, пока дерётся другой; арена держит флаг независимо.
- `entities/bosses/boss_base/boss_arena.gd`:
  - Подписка на `EventBus.player_died`: бой прерывается, босс останавливается (`fight_active = false`), барьеры открываются, `GameState.reset_combat_state()`.
  - `_exit_tree` отписывается от сигнала (флаг/барьеры — как раньше).
- `world/zones/zone_05_finale/zone_05_arena.gd`:
  - Добавлен отсутствовавший `_exit_tree`: выход из зоны 5 в бою снимает `in_combat`.
  - Подписка на `EventBus.player_died`: прерывание боя, открытие барьеров, `reset_combat_state()`; `fight_finished` эмитится только если бой был активен.
- `entities/player/player_interaction.gd` и `world/props/bonfire.gd` не менялись: они уже читают `GameState.in_combat`/`can_save()`, теперь флаг выставляется обычными врагами.

**MINOR-06 — i-frames гасят knockback/flash**

- `core/combat/hurtbox.gd`:
  - `receive_damage()` проверяет `is_invulnerable()` цели (Player в roll/dash) **до** сигнала `damaged` и возвращает `false` — урон не проходит и реакции не применяются.
  - Повторная проверка после `damaged` — defence-in-depth, если сигнал сменил состояние.
  - Вне i-frames knockback/вспышка применяются как раньше; проверка работает через `has_method("is_invulnerable")`, поэтому враги/боссы без такого метода не затронуты.

### Тесты и проверки

- Новый `game/tests/integration/test_ec06_combat.gd` — 5 GUT-тестов, 47 asserts:
  1. обычный враг агрится → `in_combat=true`, `Bonfire.can_save()==false`, `save_to_slot()` отклонён с `save_failed(slot,"in_combat")` и без записи файла, `PlayerInteraction.can_interact()==false`;
  2. два агрессора → после смерти первого `in_combat` остаётся true, после второго — false (refcount);
  3. смерть в финальной арене (`player_died`) → `in_combat=false`, бой/босс прерваны, барьеры открыты, `Bonfire.save_to_slot()` реально пишет слот;
  4. `queue_free()` зоны 5 в бою → `_exit_tree` снимает `in_combat`;
  5. roll i-frames → HP/velocity/вспышка не меняются, после i-frames knockback и урон применяются.
- Окружение: портативный **Godot 4.4.1.stable** (`GODOT_PATH`), из `game/`:
  - `--headless --path <worktree>/game --import` → exit 0.
  - GUT `-gdir=res://tests -ginclude_subdirs -gexit` → **523/523 passed, 7107 asserts**, exit 0 (было 518, +5).
  - `test_ec06_combat.gd` отдельно → 5/5, 47 asserts, SCRIPT ERROR 0.
  - `docs/init.ps1` c `GODOT_PATH` → exit 0, GUT 523/523.
  - Smoke `--headless --path game --quit-after 240` → exit 0, SCRIPT ERROR 0.
  - Leak-сообщения Godot при выходе (`RID allocations…`, `ObjectDB instances leaked`) — известный шум headless (N6), exit code 0, к нашим изменениям не относится.

### Кросс-файловые правки (на контроль Guardian)

- `autoload/GameState.gd` — новый публичный контракт боя (`set_combat_source`, `is_combat_source_active`, `reset_combat_state`, изменённая семантика `set_in_combat(false)`).
- `entities/enemies/base/enemy.gd` — producer боя/подписка на `player_died`/`_exit_tree`.
- `entities/bosses/boss_base/boss_arena.gd`, `world/zones/zone_05_finale/zone_05_arena.gd` — прерывание боя по смерти, `_exit_tree` зоны 5.
- `core/combat/hurtbox.gd` — i-frame гейт реакций.
- `enemy_spawner.gd` не менялся: producer в базовом `Enemy` покрывает всех обычных врагов, включая спавн из групп.
- Запрещённые файлы Fix-4a (`core/death/`, `SceneRouter.gd`, `Main.gd`, `ui/menus/`, `ui/death/`) не изменялись.
