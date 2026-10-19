# Fix-3a — WORKFLOW_LOG

## 2026-10-19 — Fix-3a: остаточные блокеры повторного QA N1/N3/N4/N5 (tasker-backend)

- **Ветка/worktree:** `v2` → detached worktree от `48de7dc` (Fix-3a).
- **Skills:** загружен `godot` — GDScript 4.4, `.tscn`/PackedScene, `Node2D`/`CanvasLayer`/`Control`,
  GUT/headless, шейдеры/материалы; домен задачи — игровой Godot-проект. Другие skills не нужны.
- **Задача:** исправить N1 (отмена `FactionChoice` навсегда блокирует US-06), N3 (`Teacher` отсутствует
  в мире), N4 (нет контура врагов в «Читаемость силуэтов»), N5 (источники способностей расходятся со
  SPEC §4.1); скопировать QA-отчёт в `docs/QA.md`.

### Изменения

- `game/Main.gd`: подписка на `FactionChoice.closed`; при закрытии без выбора сбрасываются
  `_faction_choice_requested` и снова взводится `_faction_choice_pending` — выбор открывается по
  следующему `quest_completed` или закрытию диалога. Подтверждённый выбор не сбрасывается.
- `game/entities/npc/teacher.gd` + `teacher.tscn`: учитель в группе `teachers`, контракт `interact()`,
  компактная панель прокачки (↑/↓, Enter/A, Esc/B), реальные `train()`/`learn_skill()` с очками и
  предусловиями (AC-08.1/08.2); пауза на время панели.
- `game/world/zones/zone_01_village/zone_01_village.tscn`: 3 учителя (quartermaster/huntress/elder)
  на маркерах у хижины и сундука.
- `game/entities/enemies/base/enemy_outline_sprite.gd` + `enemy.tscn`/`enemy.gd`: контурный материал
  `SilhouetteOutline` на `Enemy/Visual`, управляется `Config.silhouette_readability`; плейсхолдер врага
  получил 1-px alpha-рамку, чтобы контур был видимым.
- `zone_02_swamp.tscn` / `zone_03_mountains.tscn`: `wall_climb` перенесён в зону 2 (опциональный
  секрет за dash-gate), у источников/гейтов добавлены metadata `source`/`ability_source` по SPEC §4.1.
- `docs/QA.md`, `game/tests/e2e/QA_48de7dc_proposed.md`: копия QA-отчёта без правок содержимого.

### Проверки

- `--headless --import`: exit 0, без parse/script-ошибок.
- GUT: **518/518 passed, 7060 asserts**, exit 0 (portable Godot 4.4.1).
- `qa_probe`: зона 1 — `teachers=["TeacherQuartermaster","TeacherHuntress","TeacherElder"]`;
  зона 2 — `pickups=["AbilityPickupDash","AbilityPickupWallClimb"]`; зона 3 — pickups пусто.
- `qa_a11y`: **106 pass / 0 fail**, включая «контур врагов (DESIGN §9.1)».
- Smoke-проба Fix-3a: interact открывает панель учителя (пауза/закрытие), тренировка `str 5 → 6`,
  предусловие навыка «ТРЕБУЕТСЯ: СИЛА 8 (у вас 6)», отмена фракции сбрасывает флаг, контур врага
  следует тумблеру, `wall_climb` в зоне 2; exit 0.
- Ограничения: e2e-скрипт QA, ожидающий `wall_climb` в зоне 3, требует обновления под SPEC §4.1;
  полный 10-минутный FPS/4-часовой soak не выполнялись.
