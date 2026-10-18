# T-11 — блок и парирование

## 2026-10-18 · Tasker (backend)

- **Skills:** загружен `godot` (типизированный GDScript 4.4+, `RefCounted`-логика
  боя, `CharacterBody2D`/FSM, `Area2D` hitbox/hurtbox, autoload `GameState`/
  `AudioManager`, GUT/headless). Другие skills не требовались: `react`,
  `postgres`, `go`, `python`, `docker` — N/A (задача чисто Godot-бой + GUT).
- **Задача:** T-11 «Блок и парирование» (`docs/TASKS.json`; PLAN §3.1/§3.3;
  SPEC US-03, AC-03.2/03.3; DESIGN §7). Статус в `docs/TASKS.json` не менялся
  (`pending` до независимых QA/Guardian).
- **Реализация:**
  - `game/core/combat/block.gd` — `Block` (RefCounted): настройка из
    `balancing.tres`, передняя дуга `block_arc_degrees` (120°), окно
    парирования `t_parry` (0.18 с), снижение урона на `p_block` % (80 %),
    стоимость активации `stamina_cost`/`can_activate()` (`E_block`, AC-03.3),
    `resolve_incoming()` → `{blocked, parried, amount, absorbed}`. Парирование
    расходуется один раз на активацию блока; счётчики `parry_count`/
    `blocked_count` для QA/HUD-фидбека.
  - `game/entities/player/states/block.gd` — удержание блока, вход открывает
    окно парирования, выход закрывает; в окне контратаки `attack` запускает
    бесплатный удар; roll/dash/hurt/death по-прежнему прерывают блок.
  - `game/entities/player/Player.gd` — `receive_hit()` как единая точка входа
    урона: парирование гасит урон полностью, обычный блок снижает его на
    `P_block` % и **не** переводит в Hurt; попадание вне передней дуги идёт
    полным уроном. Успешное парирование открывает окно контратаки `t_counter`
    (0.4 с) и вызывает `AudioManager.play_sfx(&"parry")`.
  - `game/entities/player/PlayerAnimation.gd` — `play_parry_spark()`:
    искра-вспышка steel-3 из 3 частиц на 2 кадра блока (DESIGN §7),
    счётчик `parry_spark_count` для тестов.
  - `game/data/balance/balancing_params.gd` + `balancing.tres` — добавлены
    `p_block = 80.0`, `block_arc_degrees = 120.0`, `t_counter = 0.4`
    (P_block отсутствовал в данных T-10, хотя упоминался в описании задачи).
- **Ключевое поведение (acceptance):**
  - AC-03.2: блок в передней дуге снижает урон на `P_block` %; `E_block`
    списывается при входе в блок (существующий `Player.try_block()`/T-10).
  - Парирование внутри `T_parry`: урон 0, окно расходуется, открывается
    контратака (`attack` без `E_attack`), играет SFX `parry` и искра.
    Вне окна — обычный блок с `P_block` %.
  - AC-03.3: при выносливости 0 `try_spend_stamina(E_block)` возвращает false,
    состояние `block` не стартует, флаг «НЕТ СИЛ» поднят.
- **Тесты:** новый `game/tests/unit/test_block_parry.gd` — 9 тестов, 73 asserts:
  чистая логика `Block` (P_block, окно внутри/вне, расход парирования, дуга,
  нехватка `E_block`), интеграция на реальных 60 Hz кадрах (списание E_block,
  снижение урона и HP, парирование без урона + контратака + SFX + искра,
  атака сзади, отказ при 0).
- **Evidence (portable Godot 4.4.1-stable, `GODOT_PATH`):**
  - рабочее дерево (до появления правок другой сессии в `project.godot`):
    `--headless --path game --import` — exit 0 без script/parse-ошибок;
    `test_block_parry` — **9/9 passed, 73 asserts**; полный GUT до финальной
    правки — **495/495, 5187 asserts**; `--headless --path game --quit` —
    exit 0, script-ошибок нет (только штатный engine-leak warning при
    немедленном выходе).
  - **чистый worktree** `C:\...\Temp\opencode\t11-clean` на коммите `5c1398e`:
    `--import` exit 0; GUT **496/496 passed, 5192 asserts** (487/5119 до T-11,
    +9 тестов/73 asserts); smoke `--quit` exit 0.
- **Найденные/исправленные проблемы:** (1) `P_block` не был заведён в
  `BalancingParams`/`balancing.tres` (описание T-10 упоминало его, но поля не
  было) — добавлен как данные; (2) каркас `states/block.gd` из T-04 не
  участвовал в уроне — урон теперь проходит через `Player.receive_hit()`;
  (3) блок не должен прерываться обычным заблокированным ударом — Hurt
  запускается только при непоглощённом/заднем попадании.
- **Кросс-файловые правки:** `data/balance/balancing_params.gd`,
  `data/balance/balancing.tres`, `entities/player/Player.gd`,
  `entities/player/PlayerAnimation.gd`, `entities/player/states/block.gd`.
  Новые: `core/combat/block.gd` (+`.uid`),
  `tests/unit/test_block_parry.gd` (+`.uid`). `docs/TASKS.json`, `EventBus.gd`,
  `GameState.gd`, `ui/inventory/` (T-21) и чужие файлы не менялись.
- **Ограничения:** (1) `E_block` — одна оплата на активацию удержания, а не за
  каждое заблокированное попадание (совместимо с тестом T-10 и трактовкой
  AC-03.2); блок недоступен при остатке меньше `E_block` (8), не только при 0;
  (2) контратака — бесплатный обычный удар без множителя урона (множитель не
  задан требованиями/данными); (3) дуга блока — логическая (120°), отдельного
  визуального щита/сектора нет; искра — программная заглушка steel-3;
  (4) парирование не эмитит отдельного сигнала `EventBus` (HUD-фидбек не
  входил в T-11); (5) независимые приёмка QA и ревью Guardian Tasker'ом не
  выполнялись.
- **Параллельность:** в рабочем дереве присутствовали незакоммиченные правки
  других сессий (`docs/WORKFLOW_LOG.md`, затем `game/project.godot`,
  `game/assets/locale/*`, `game/tests/_probe_locale.gd`) и untracked
  `opencode.jsonc` — не трогались; `ui/inventory/` не изменялся (T-21 уже в
  HEAD `96d8a9d`). Все evidence-прогоны выполнены в чистом worktree на
  коммите T-11, без чужих файлов.
- **Коммит:** `5c1398e` «T-11: блок и парирование»; запись журнала —
  отдельным docs-коммитом.
