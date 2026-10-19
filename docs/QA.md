# QA: «Пепельный Бастион» — сквозная приёмка T-37

**Проверенная ревизия (повторный прогон):** `48de7dc5757e11ba9a55a9c010c9df9093339c69` — ветка `v2`, Integration-03 (Fix-1 `70d8d38` + Fix-2 `5f92c0e`)
**Дата:** 2026-10-19
**Окружение:** Windows, portable Godot **4.4.1.stable** (`Godot_v4.4.1-stable_win64_console.exe`, `GODOT_PATH`), проект `game/`, GUT 9.x, 480×270; для NFR/визуала — рендер OpenGL 3.3 (NVIDIA RTX 3070 Ti).
**Метод:** headless e2e + headless a11y/фикс-пробы + GUT + рендер-прогон NFR и скриншоты.

---

## Итог повторного прогона: ❌ **FAIL**

Сквозной проход «меню → зона 1 → зоны 2–5 → 5 боссов → титры» работает без вылетов, e2e **115/115**, GUT **518/518**, NFR **8/8**. Но приёмка не принимается: блокер 7 закрыт только частично, блокер 1 — частично (способности есть, `Teacher` нет), найден новый блокер в ветке US-06, и AC-08.1/08.2 по-прежнему недостижимы в игре.

| # | Блокер из прогона `c7c0d62` | Статус на `48de7dc` | Evidence |
|---|---|---|---|
| 1 | Способности/`Teacher` недостижимы | ⚠️ **частично** | `AbilityPickup` в зонах 1–3; подбор физическим входом, gates открываются (`qa_e2e`). `Teacher` по-прежнему нет ни в одной зоне: `teachers=[]` ×5 (`qa_probe`) → AC-08.1/08.2 недоступны |
| 2 | Нет обычных врагов | ✅ **исправлен** | `EnemySpawner` в зонах 1–4 (4–5 врагов); e2e: урон, смерть, XP `0 → 50`; NFR: 5 реальных врагов зоны 2 |
| 3 | Боссы 1–4 невидимы | ✅ **исправлен** | `show_placeholder_art=false`, `self_modulate.a=1.00` у всех арен; e2e 5/5 боссов видимы; на скриншоте зоны 1 босс и арена видны |
| 4 | Выбор фракции недостижим | ✅ **исправлен** (исходный блокер) | После завершения квеста `FactionChoice` открывается, выбор `free` фиксируется, концовка `ending_free`. **Но** отмена экрана навсегда блокирует выбор — новый N1 |
| 5 | Ремап недостижим | ✅ **исправлен** | «Управление» активна; Enter → `Remap`; 14 действий; Esc возвращает в настройки |
| 6 | Journal/Factions недостижимы | ✅ **исправлен** | N/F открывают и закрывают экраны в игре (пауза ставится/снимается); действия `journal`/`factions` добавлены в InputMap и ремап |
| 7 | A11y §9.6 п.6 (RU/EN 100/150%) | ❌ **не исправлен полностью** | WorldMap EN влезает (PASS), `DeathScreen._retranslate` без Nil (PASS), подсказка clamp (PASS), HUD `8 → 12 px` (PASS). Но 150% **не применяется** к Inventory/Journal/Factions/FactionChoice/WorldMap/Campfire/Remap/DeathScreen: шрифты `8 → 8`, `16 → 16`, `32 → 32` px |
| 8 | AC-02.4: подсказка обрезана | ✅ **исправлен** | clamp: panel `184 px`, offset `−62 px`, экран `[294…478]` ≤ 480; текст «Нужно: ДВОЙНОЙ ПРЫЖОК» полный |
| 9 | EC-13 не реализован | ✅ **исправлен** | `FOCUS_OUT → paused=true`, `PauseMenu` создан и видим, фокус на «Продолжить», Enter снимает паузу |

**Почему FAIL:** блокер 7 (масштаб UI) закрыт только для HUD/меню; блокер 1 (Teacher → US-08) не закрыт; новый блокер N1 делает ветку US-06 необратимо недоступной после Esc/B; AC-08.1/08.2 остаются FAIL.

### Команды прогона

```powershell
$env:GODOT_PATH = "C:\Users\cudjo\AppData\Local\Temp\opencode\godot\Godot_v4.4.1-stable_win64_console.exe"
cd game

# сквозной e2e
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_e2e.tscn --quit-after 60000
# a11y §9.6
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_a11y.tscn --quit-after 40000
# точечные проверки фиксов
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_fix_probe.tscn --quit-after 30000
# независимая проверка спорных мест (UI scale, отмена выбора фракции)
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_rerun_probe.tscn --quit-after 20000
# NFR (нужен рендер)
& $env:GODOT_PATH --path . res://tests/e2e/qa_nfr.tscn --quit-after 90000
# GUT
& $env:GODOT_PATH --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

Логи прогона: `...\Temp\opencode\qa_rerun_e2e.log`, `qa_rerun_a11y.log`, `qa_rerun_fix.log`, `qa_rerun_probe2.log`, `qa_rerun_nfr.log`, `qa_rerun_gut.log`.

---

## 1. По девяти блокерам (детально)

### B1. Способности и `Teacher` — ⚠️ частично

- **Способности: исправлено.** `qa_probe` на `48de7dc`:
  - `zone_01_village`: `AbilityPickupDoubleJump`;
  - `zone_02_swamp`: `AbilityPickupDash`;
  - `zone_03_mountains`: `AbilityPickupWallClimb`.
- `qa_e2e` проходит подбор как игрок (вход в `Area2D`), а не через `GameState.add_ability()`: `double_jump`, затем `dash`, затем `wall_climb`; после каждого подбора соответствующий gate (`Rubble`, `DashGate`, `WallClimbGate`) `open=true`.
- **`Teacher`: не исправлено.** `qa_probe` у всех пяти зон даёт `teachers=[]`. В проекте есть `game/entities/npc/teacher.gd` и данные `game/data/balance/teachers/{elder,huntress,quartermaster}.tres`, но нет `teacher.tscn` и ни одного инстанса в зонах. Следствие: AC-08.1/08.2 (трата очков обучения, рост стоимости, предусловия навыка) недостижимы в игровом потоке — только в GUT (`test_progression`).

### B2. Обычные враги — ✅ исправлено

- `qa_probe`: `EnemySpawner` и враги в зонах 1–4:
  - зона 1: 4 врага (swift×2, heavy, ranged);
  - зона 2: 5 врагов (swift×2, undead×2, ranged);
  - зона 3: 4 врага;
  - зона 4: 5 врагов.
- `qa_e2e`: атака игрока ранит и убивает `SwiftEnemy` в мире; XP `0 → 50`; враги не QA-спавн, а из сцены зоны.
- NFR-прогон: «бой: 5 реальных врагов из зоны 2» — 5.

### B3. Видимость боссов 1–4 — ✅ исправлено

- В сценах зон 1–4 `self_modulate = Color(1,1,1,0)` заменён на `show_placeholder_art = false`; `boss_arena.gd` скрывает только собственную заглушку фона, не детей.
- `qa_e2e` для всех пяти арен: `arena.self_modulate.a=1.00`, `boss_visible=true`.
- Рендер-скриншот зоны 1: видны арена и босс (красный силуэт), HUD-бар «Пепельный Страж». Файл `user://qa_t37_boss_zone1.png` (копия: `...\Temp\opencode\qa2_boss1.png`).

### B4. Выбор фракции — ✅ исходный блокер исправлен, но есть новый N1

- `qa_e2e`: квест `quest_free_smuggle` завершён, репутация `free 0 → 15`, затем без ручного вызова UI открывается `FactionChoice` (`open=true`, `paused=true`); выбор `free` фиксируется, экран закрывается, пауза снимается; финал учитывает фракцию: `ending_free`, титры `finished`.
- **Новый дефект N1:** Esc/B на экране выбора («закрыть без выбора», задокументировано в `FactionChoice.gd`) навсегда блокирует повторный выбор. Подробности и repro — §7.

### B5. Ремап — ✅ исправлено

- `qa_e2e`: строка «Управление» `disabled=false`, `reason=''`; Enter открывает `Remap`; перечислены 14 действий, включая `journal`/`factions`; Esc закрывает ремап и возвращает настройки.
- GUT: `test_settings_remap_opens_remap_screen`, `test_remap_assigns_event_and_persists_to_settings` — PASS.

### B6. Journal/Factions — ✅ исправлено

- `qa_e2e`: N открывает журнал (`open=true`, `paused=true`), повторная N закрывает и снимает паузу; F аналогично для фракций; I — инвентарь.
- InputMap: добавлены действия `journal` (N / L3) и `factions` (F / R3); они же в ремапе. Экраны не открываются поверх диалога/костра (проверка `_other_modal_open`).

### B7. A11y §9.6 п.6 — ❌ не исправлен полностью

Три подпункта прошлого блокера:

1. **WorldMap EN — исправлено.** `qa_a11y`: «переполнение EN/100%» и «EN/150%» — PASS; кнопка зоны расширена до 160 px, панель `LEFT_RECT` 164 px.
2. **`DeathScreen._retranslate` — исправлено.** `qa_fix_probe`: строки потерь инициализированы; EN `Coins`/`Items`, возврат RU `Монеты`; runtime-ошибки `Invalid assignment ... Nil` нет.
3. **Масштаб UI 150% — не исправлено для большинства экранов.** HUD исправлен (`8 → 12 px`), меню/настройки/слоты уже масштабировались. Но при `Config.ui_scale = 150`:
   - Inventory `8 → 8 px`;
   - Journal `16 → 16 px`;
   - Factions `16 → 16 px`;
   - FactionChoice `16 → 16 px` (по `qa_fix_probe`);
   - WorldMap `16 → 16 px`;
   - Campfire `8 → 8 px`;
   - Remap `16 → 16 px`;
   - DeathScreen `32 → 32 px`.

   В коде `Config.ui_scale` читают только `MainMenu`, `Settings`, `SaveSlots` и `HUD`; остальные экраны не подписаны на `ui_scale_changed` и не пересчитывают `font_size`/контейнеры. Поэтому «переполнение панелей RU/EN/150%» в `qa_a11y` проходит **вакуумно**: текст на этих экранах не увеличивается.

### B8. AC-02.4: подсказка gate — ✅ исправлено

- `qa_fix_probe`: `AbilityHint` у завала; `show_required(double_jump)` + `set_world_position(448,170)`; panel `(184,13)`, offset `(-62,0)`, экранный прямоугольник `[294…478]×[163.5…176.5]` внутри `480×270`; текст «Нужно: ДВОЙНОЙ ПРЫЖОК» полный.
- `AbilityHint._update_offset()` clamp-ит панель к `viewport.get_visible_rect()` с отступом 2 px.

### B9. EC-13 — ✅ исправлено

- `qa_fix_probe`: `propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` → `paused=true`; `PauseMenu` (CanvasLayer 50) создан и видим; фокус на `Root/Center/Panel/Box/Resume`; Enter снимает паузу и скрывает меню.
- Реализация в `Main._notification` / `_on_focus_lost` / `_open_pause_menu`; меню `PROCESS_MODE_ALWAYS`.

---

## 2. Сквозной проход (как игрок)

`qa_e2e.tscn`: **115/115 PASS**, вылетов и блокировок нет.

| Шаг | Результат | Evidence |
|---|---|---|
| Меню → навигация клавиатурой/геймпадом | ✅ | фокус `New/Load/Settings/Exit/LangRU`, D-pad ↓/↑ |
| Настройки → «Управление» → Remap → Esc | ✅ | 14 действий, возврат в настройки |
| «Новая игра» → `Main.tscn` | ✅ | зона 1, `abilities=[]` |
| Зона 1: движение, прыжок, HUD | ✅ | x `100 → 130`; y `213.9 → 185.5`; HUD/Campfire/Dialogue/DeathHandler |
| Двойной прыжок: подбор → gate | ✅ | вход в `AbilityPickupDoubleJump`; `Rubble.open=true` |
| Бой: 4 врага зоны 1 | ✅ | урон, смерть, XP `0 → 50` |
| N/F/I: журнал/фракции/инвентарь | ✅ | открытие/закрытие, пауза корректна |
| Костёр → слот 1 → загрузка | ✅ | слот `valid=true`, schema 6; валюта восстановлена |
| Смерть → экран → respawn → corpse run | ✅ | 2 предмета + 42 монеты в corpse; подбор вернул всё |
| Диалог → квест → репутация → выбор фракции | ✅ | `free 0 → 15`; `FactionChoice` открылся; выбран `free` |
| 5 боссов: арены, фазы, победа | ✅ | 5/5; у каждого «ФАЗА II»; все отмечены побеждёнными |
| Переходы зон (физические выходы) | ✅ | 1→2 `0.416 с`, 2→3 `0.607 с`, 3→4 `0.469 с`, 4→5 `0.717 с` (≤ 3 с) |
| Финал → фракционная концовка → титры | ✅ | `ending_free`, `finished`; вылетов нет |

---

## 3. A11y-чек-лист DESIGN §9.6

`qa_a11y.tscn`: **105 PASS / 1 FAIL** (FAIL — контур врагов, см. N4).

| № | Пункт §9.6 | Статус | Evidence |
|---|---|---|---|
| 1 | Любой экран только клавиатурой и только геймпадом | ✅ PASS | MainMenu, Settings, SaveSlots, Campfire, Dialogue, DeathScreen, Inventory, Journal, Factions, FactionChoice, WorldMap, Remap: фокус и D-pad-навигация |
| 2 | Фокус виден на каждом интерактивном элементе | ✅ PASS | у всех проверенных владельцев `has_focus=true`, `is_focus_visible()=true` |
| 3 | 8-px текст ≥ 4.5:1 на фактическом фоне | ✅ PASS | минимум `blood-5/night` **4.59:1**; тема Label 11.29, Muted 6.60, Danger 5.19, Gold 9.71, Steel 6.26 |
| 4 | Нет состояния, различимого только цветом | ✅ PASS | «НЕТ СИЛ» + «!»; «КРИТИЧНО»; число HP; фокус-каретка «>» + скобки |
| 5 | «Без мигания»: нет вспышек > 3 Гц | ✅ PASS | HP-крит не мигает; `FlashGovernor` 3/8; `flame_multiplier=1.0`; свет зоны ровный; смерть без fade |
| 6 | RU/EN помещаются во все панели при 100/150% | ❌ **FAIL** | WorldMap EN — PASS, `DeathScreen` — PASS, подсказка — PASS; но UI 150% не применяется к 8 экранам (§B7), поэтому проверка «150%» для них недействительна |
| 7 | Герой отличим от фона при штатной яркости | ✅ PASS | виньетка `0.28 → 0.00` в режиме читаемости; контур игрока включён. **Расхождение N4:** контура врагов нет |

Дополнительно: `Config.no_flash` отключает мигание HP, мерцание света, fade смерти и печать текста; `Config.silhouette_readability` отключает виньетку и включает outline игрока.

---

## 4. NFR

`qa_nfr.tscn` (рендер): **8/8 PASS**.

| Метрика | Требование | Замер | Статус |
|---|---|---|---|
| Старт до меню | ≤ 10 с | 77 мс (инициализация сцены после запуска движка) | ✅ |
| Загрузка зоны | ≤ 3 с | `SceneRouter`: 0.057–0.132 с; физические выходы e2e: 0.416–0.717 с | ✅ |
| FPS в бою с 5 врагами | ≥ 60; p95 ≥ 55 | avg **680.7**, p50 **660**, p95 **720** (20 с, 13 356 кадров, vsync off) | ✅ |
| 20 циклов save/load | утечка ≤ 10% | static memory **58 337 679 → 58 341 351 байт (+0.01%)**, objects **3385 → 3385** | ✅ |
| 5 врагов в бою | — | 5 реальных врагов из `EnemySpawner` зоны 2 (не QA-спавн) | ✅ |

Ограничения: 10-минутный FPS-прогон и 4-часовой soak не выполнялись; FPS — 20 с, save/load — 20 циклов. Запас по FPS и памяти многократный.

---

## 5. GUT-базлайн

```powershell
cd game
& $env:GODOT_PATH --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**518/518** (45 скриптов, 7060 asserts, 130.8 с), exit code **0**. Юниты покрывают FSM, способности, бой, сейвы, UI, но не заменяют e2e: остаточные дефекты — интеграционные.

При завершении headless-прогонов остаются `ERROR: ... RID allocations ... leaked at exit`, `ObjectDB instances leaked`, `resources still in use`; e2e/a11y/пробы завершаются с exit code 1 (GUT в этом прогоне — 0). Это риск для CI, если он проверяет код возврата (N6).

---

## 6. Обновлённая матрица трассируемости AC (SPEC §3)

| AC | Статус | Evidence |
|---|---|---|
| AC-01.1 движение | ✅ PASS | e2e: x `100 → 130` |
| AC-01.2 прыжок H_jump ±1 px | ✅ PASS (GUT) | `test_player_movement` |
| AC-01.3 геймпад + ремап | ✅ PASS | геймпад: движение/прыжок; ремап открывается и персистит |
| AC-01.4 буфер ввода 150 мс | ✅ PASS (GUT) | `test_input_buffer` |
| AC-02.1 двойной прыжок | ✅ PASS | pickup + GUT `test_double_jump_*` |
| AC-02.2 dash + i-frames + C_dash≤1 с | ✅ PASS | pickup + GUT `test_dash_*` |
| AC-02.3 wall slide/kick | ✅ PASS | pickup + GUT `test_wall_climb_*` |
| AC-02.4 gate блокирует и показывает подсказку | ✅ PASS | clamp, полный текст, gate `open=true` |
| AC-03.1 урон/реакция ≤100 мс | ✅ PASS | враги в мире; e2e урон/смерть/XP |
| AC-03.2 блок/парирование | ✅ PASS (GUT) | `test_block_parry` |
| AC-03.3 stamina 0 → «НЕТ СИЛ» | ✅ PASS | a11y-бейдж |
| AC-03.4 фазы боссов + HUD | ✅ PASS | 5/5, «ФАЗА II» |
| AC-04.1 способность открывает путь, T_load≤3 с | ✅ PASS | gates открыты; переходы ≤0.72 с |
| AC-04.2 карта посещённых зон | ✅ PASS | `test_map`, a11y WorldMap |
| AC-04.3 все gates после способности | ✅ PASS | e2e: 3/3 gate `open=true` |
| AC-05.1 сохранение/загрузка | ✅ PASS | слот 1 schema 6, `valid=true` |
| AC-05.2 смерть → экран → respawn, лут в corpse | ✅ PASS | 2 предмета + 42 монеты |
| AC-05.3 corpse run | ✅ PASS | лут подобран |
| AC-06.1 квест → репутация/NPC | ✅ PASS | `free 0 → 15`; выбор фракции открывается (но N1: отмена необратима) |
| AC-06.2 доступ по репутации | ✅ PASS (GUT/UI) | `test_factions`; экран фракций достижим по F |
| AC-07.1 палитра/читаемость героя | ✅ PASS | палитры зон; герой виден; контур героя (N4 — врагов нет) |
| AC-07.2 кроссфейд музыки ≤2 с | ✅ PASS (GUT) | `test_audio` |
| AC-08.1 прокачка у учителя | ❌ **FAIL (интеграция)** | `Teacher` нет ни в одной зоне; логика только в GUT |
| AC-08.2 требования навыка/экипировки | ❌ **FAIL (доступность UI)** | нет учителя/экрана прокачки в мире |
| AC-09.1 FPS 5 врагов | ✅ PASS | p95 720, avg 680.7 |
| AC-09.2 20 save/load, память | ✅ PASS | +0.01%, objects 3385→3385 |
| EC-13 потеря фокуса окна | ✅ PASS | пауза + PauseMenu + Resume |

---

## 7. Новые расхождения и шаги воспроизведения

### N1. Отмена выбора фракции навсегда блокирует US-06 — **блокер**

**Симптом.** Игрок завершает квест, `FactionChoice` открывается. Если нажать Esc/B (экран сам предлагает «закрыть без выбора»), экран закрывается, выбор не сделан. После этого открыть его снова нельзя: `Main._faction_choice_requested` уже `true`, повторный `quest_completed` идемпотентен, а экран «Фракции» (F) не содержит действия выбора. Фракционная концовка становится недоступной до конца забега (остаётся нейтральная).

**Код.**
- `game/Main.gd:66-68` — ранний выход, если `_faction_choice_requested`;
- `game/Main.gd:85-89` — флаг ставится до `emit`, не сбрасывается при отмене;
- `game/ui/factions/FactionChoice.gd:116-124` — `close()` без выбора;
- `game/ui/factions/FactionChoice.gd:167-169` — Esc/B закрывает;
- `game/autoload/FactionManager.gd:394` — `choose_faction()` вызывается только из `FactionChoice`.

**Воспроизведение.**
```powershell
cd game
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_rerun_probe.tscn --quit-after 20000
```
Факт:
```
[PROBE2] PASS faction cancel: экран выбора открылся после квеста — open=true
[PROBE2] PASS faction cancel: Esc закрывает экран без выбора — open=false chosen=false
[PROBE2] PASS faction cancel: повторный запрос заблокирован флагом Main — _faction_choice_requested=true
[PROBE2] PASS faction cancel: выбор нельзя вернуть после отмены — open=false chosen=false
```
(PASS здесь — подтверждение наблюдаемого поведения; с точки зрения US-06 это дефект.)

**Ожидание:** либо отмена не закрывает экран/показывает предупреждение о необратимости, либо выбор можно открыть повторно (например, из экрана «Фракции» или по новому сюжетному событию). Нужен e2e-сценарий «отмена → повторное открытие → выбор».

### N2. UI 150% не масштабирует 8 экранов — **блокер (часть B7)**

**Симптом.** Настройки → «Масштаб интерфейса» → 150%. HUD увеличивается (`8 → 12 px`), но Inventory, Journal, Factions, FactionChoice, WorldMap, Campfire, Remap, DeathScreen остаются в базовом размере.

**Код.** `Config.ui_scale` читают только `MainMenu.gd`, `Settings.gd`, `SaveSlots.gd`, `HUD.gd`; в остальных UI-скриптах нет `ui_scale`/`ui_scale_changed`.

**Воспроизведение.**
```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_rerun_probe.tscn --quit-after 20000
```
Факт:
```
[PROBE2] FAIL ui 150%: Inventory — font 8 → 8 px
[PROBE2] FAIL ui 150%: Journal — font 16 → 16 px
[PROBE2] FAIL ui 150%: Factions — font 16 → 16 px
[PROBE2] FAIL ui 150%: WorldMap — font 16 → 16 px
[PROBE2] FAIL ui 150%: Campfire — font 8 → 8 px
[PROBE2] FAIL ui 150%: Remap — font 16 → 16 px
[PROBE2] FAIL ui 150%: DeathScreen — font 32 → 32 px
```
`qa_fix_probe` дополнительно фиксирует FactionChoice `16 → 16` (итого 8 экранов, 8 FAIL из 20).

### N3. `Teacher` отсутствует в мире — **блокер US-08 / AC-08.1–08.2 (часть B1)**

**Симптом.** Очки обучения начисляются за XP, но потратить их в игре негде: ни в одной зоне нет `Teacher`, экрана прокачки нет. Прокачка существует только в GUT.

**Evidence.**
```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_probe.tscn
```
Факт: `zone_01_village ... teachers=[]`, `zone_02_swamp ... teachers=[]`, `zone_03_mountains ... teachers=[]`, `zone_04_ruins ... teachers=[]`, `zone_05_finale ... teachers=[]`.
В проекте есть `game/entities/npc/teacher.gd` и `game/data/balance/teachers/*.tres`, но нет `teacher.tscn` и ни одного инстанса в сценах зон.

**Ожидание:** разместить учителей (или явно вывести US-08 из MVP решением человека и обновить SPEC/PLAN). Без этого AC-08.1/08.2 не принимаются.

### N4. Нет контура врагов в «Читаемость силуэтов» — расхождение с DESIGN §9.1

`qa_a11y`: «силуэты: контур врагов (DESIGN §9.1)» — **FAIL**: у `Enemy`/`EnemyAnimation` нет `is_silhouette_outline_enabled`; `SilhouetteOutline` применяется только в `PlayerAnimation.gd`. Пункт §9.6 п.7 при этом PASS: герой отличим от фона (виньетка `0.28 → 0.00`, контур игрока включён). Не блокирует §9.6, но остаётся расхождением с §9.1.

### N5. Источники способностей отличаются от SPEC §4.1

SPEC §4.1: dash — «Квест учителя/NPC, зона 2»; wall_climb — «Опциональный секрет, зона 2». Фактически: dash — `AbilityPickupDash` в зоне 2, wall_climb — `AbilityPickupWallClimb` в зоне 3. Прохождение работает, но источник/зона не совпадают с таблицей; требует решения: обновить SPEC или перенести pickup.

### N6. Утечки при выходе headless-прогонов — риск CI

При завершении e2e/a11y/проб: `ERROR: N RID allocations ... leaked at exit`, `ObjectDB instances leaked`, `resources still in use at exit`; exit code 1. GUT в этом прогоне — 518/518 и exit 0. Во время игры падений нет. Если CI проверяет код возврата e2e/проб, шаг будет красным.

---

## 8. Что нужно для PASS

1. **UI scale:** применить `Config.ui_scale` (font_size/контейнеры, шаг 8 px) к Inventory, Journal, Factions, FactionChoice, WorldMap, Campfire, Remap, DeathScreen; добавить проверку реального роста шрифта, а не только отсутствия переполнения.
2. **FactionChoice:** не терять выбор при Esc/B — либо запретить закрытие без выбора с предупреждением, либо дать повторный вход (экран «Фракции»/сюжетный сигнал); e2e «отмена → повторное открытие → выбор → фракционная концовка».
3. **Teacher/US-08:** разместить учителей и экран прокачки в мире (AC-08.1/08.2) либо официально вывести US-08 из MVP и обновить SPEC/PLAN.
4. **Опционально:** контур врагов (DESIGN §9.1), выравнивание источников способностей с SPEC §4.1, устранение leak-сообщений/exit code.
5. Повторить `qa_e2e`, `qa_a11y`, `qa_nfr`, `qa_rerun_probe` и GUT на новой ревизии; обновить SHA в этом отчёте.

---

# Приложение. Архивный прогон на `c7c0d62` (Integration-02)

**Проверенная ревизия:** `c7c0d622b68a7e190744651a4f4f7b76a4921fa1` (Integration-02)
**Дата:** 2026-10-19
**Окружение:** Windows, portable Godot **4.4.1.stable** (`Godot_v4.4.1-stable_win64_console.exe`, `GODOT_PATH`), проект `game/`, GUT в `game/addons/gut/`.
**Метод:** headless e2e + headless a11y/NFR-скрипты + визуальный прогон с рендером (OpenGL 3.3, NVIDIA RTX 3070 Ti) + GUT-базлайн.

---

## Итог: ❌ **FAIL**

Сквозной проход **не принимается**. Критические блокеры:

1. **Способности невозможно получить в игре:** ни в одной зоне нет `AbilityPickup` и ни одного `Teacher`. Есть только `ability_pickup.tscn` и `teacher.gd` как неиспользуемые заготовки. Следствие: двойной прыжок/dash/карабканье недостижимы, зоны 4–5 и 2 босса недоступны нормальным прохождением.
2. **В мире нет обычных врагов:** во всех пяти зонах `Enemy`/`EnemySpawner` отсутствуют. Бой с врагами, опыт, уровни и очки обучения как игровой поток недостижимы. FPS-тест с 5 врагами пришлось делать с искусственным спавном.
3. **Боссы 1–4 невидимы:** арены в зонах 1–4 имеют `self_modulate = Color(1, 1, 1, 0)`, из-за чего прозрачны и арена, и босс. Виден только HUD-бар босса. Босс 5 видим.
4. **Выбор фракции недостижим:** экран `FactionChoice` смонтирован, но в игровом коде нет ни одного эмиттера `EventBus.faction_choice_requested` (только тесты). Квест даёт репутацию (`free +15`), но концовка всегда нейтральная; выбор фракции и её концовка недоступны.
5. **Ремап недостижим:** строка «Управление» в настройках всегда disabled с причиной «T-24», а `MainMenu._on_remap_requested()` — `pass`. Экран `Remap` существует, но открыть его из игры нельзя (AC-01.3).
6. **Журнал и экран фракций недостижимы из игры:** нет InputMap-действий/вызовов `Journal.open()` и `Factions.open()`; вкладки инвентаря «Карта/Журнал/Фракции» — disabled-заглушки. Скрипты UI работают только при прямом вызове.
7. **A11y п.6 (RU/EN 100/150%) не пройден:** EN-название зоны на карте шире кнопки (144 > 141 px), масштаб UI 150% не применяется к HUD и другим экранам (шрифт остаётся 8 px), а смена языка на смонтированном `Main` даёт runtime-ошибку в `DeathScreen._retranslate()` (строки 617–618) и не переводит подписи строк смерти.
8. **AC-02.4:** подсказка «Нужно: ДВОЙНОЙ ПРЫЖОК» над завалом в зоне 1 обрезается правым краем экрана.
9. **EC-13 не реализован:** потеря фокуса окна не ставит паузу и не открывает меню.

При этом GUT-юниты — **518/518**, сквозной сценарий (с QA-инъекцией способностей) доходит до титров без падений, save/load/corpse run и 5 боссов механически работают, NFR-замеры с запасом проходят.

---

## 1. Сквозной проход (как игрок)

Команда:

```powershell
$env:GODOT_PATH="C:\Users\cudjo\AppData\Local\Temp\opencode\godot\Godot_v4.4.1-stable_win64_console.exe"
cd game
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_e2e.tscn --quit-after 20000
```

Результат: **90 проверок, 83 PASS, 7 FAIL** (плюс отдельно найденные блокеры B2/B6/B8, не входившие в счётчик).

| Шаг | Результат | Evidence |
|---|---|---|
| Меню → «Новая игра» | ✅ PASS | `MainMenu` открыт; фокус «Новая игра»; клавиатура ↓/↑ (`New/Load/Settings/Exit/LangRU`) и геймпад D-pad ↓/↑; Enter → `Main.tscn`, зона 1 |
| Зона 1: спавн, движение, прыжок, HUD | ✅ PASS | игрок в `zone_01_village`; x `100 → 130`; прыжок y `213.9 → 185.5`; HUD/Campfire/DialogueScreen/DeathHandler смонтированы |
| Получение 3 способностей | ❌ **FAIL** | `AbilityPickup`/`Teacher` в дереве всех зон: `[]`; способности введены только через `GameState.add_ability()` как QA-обход |
| Бой с обычными врагами | ❌ **FAIL** | `Enemy`/`EnemySpawner` в зонах: `[]`; боевые механики есть только в GUT и на боссах |
| Костёр → сохранение | ✅ PASS | `interact` → Campfire; чекпоинт `(112,212)`; слот 1 `valid=true`, schema 6; загрузка восстанавливает состояние |
| Смерть → экран смерти → возрождение | ✅ PASS | `dying`; экран показан; 2 предмета + 42 монеты ушли в corpse; respawn у костра, HP 100 |
| Corpse run | ✅ PASS | метка на `(112,214)`; подбор вернул 2 предмета и 42 монеты |
| Диалог/квест | ✅ PASS | `elder_lira`: взят и завершён `quest_free_smuggle`; репутация `free 0 → 15` |
| Фракции/выбор | ❌ **FAIL** | экран `FactionChoice` есть, но не открывается; эмиттера `faction_choice_requested` в игровом коде нет |
| 5 боссов: арены/фазы/победа | ✅ механически PASS | `zone_01_warden`, `zone_02_witch`, `zone_03_avalanche`, `zone_04_seal_warden`, `zone_05_sovereign`; у всех смена фазы «ФАЗА II»; все отмечены побеждёнными |
| Видимость боссов 1–4 | ❌ **FAIL** | `self_modulate.a=0.00` у арен зон 1–4; на скриншоте виден только бар «Пепельный Страж», босса и арены нет |
| Переходы зон (физические выходы) | ✅ PASS | zone1→2 `0.586 с`, 2→3 `0.441 с`, 3→4 `0.528 с`, 4→5 `0.826 с` (все ≤ 3 с) |
| Финал/концовка/титры | ✅ PASS | `EndingExit` → `ending_neutral`; титры до `finished`; вылетов нет |
| Фракционная концовка | ❌ **FAIL** | при репутации `free +15` и без выбора фракции концовка нейтральная; выбор фракции недоступен |

Дополнительный визуальный прогон (рендер, не headless):

```powershell
& $env:GODOT_PATH --path game res://tests/e2e/qa_nfr.tscn --quit-after 60000
```

Скриншоты: `C:\Users\cudjo\AppData\Local\Temp\opencode\qa_t37_menu.png`, `qa_t37_zone1.png`, `qa_t37_combat5.png`, `qa_t37_boss_zone1.png`.

---

## 2. A11y-чек-лист DESIGN §9.6

Команда:

```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_a11y.tscn --quit-after 30000
```

Итог: **102 PASS / 4 FAIL** (плюс отдельно зафиксирован runtime-дефект `DeathScreen` при смене языка).

| № | Пункт §9.6 | Статус | Evidence |
|---|---|---|---|
| 1 | Любой экран только клавиатурой и только геймпадом | ✅ PASS (для открываемых экранов) | MainMenu, Settings, SaveSlots, Campfire, Dialogue, DeathScreen, Inventory, Journal, Factions, FactionChoice, WorldMap, Remap: фокус и навигация клавиатурой + D-pad. Journal/Factions/Remap достижимы только программно (см. блокеры 5–6) |
| 2 | Фокус виден на каждом интерактивном элементе | ✅ PASS | у всех проверенных владельцев фокуса `has_focus=true`, `is_focus_visible()=true` (каретка/рамка/скобки) |
| 3 | Весь 8-px текст ≥ 4.5:1 на фактическом фоне | ✅ PASS | минимум по обязательным парам — `blood-5/night` **4.59:1**; тема: Label 11.29, Muted 6.60, Danger 5.19, Gold 9.71, Steel 6.26 |
| 4 | Нет состояния, различимого только цветом | ✅ PASS | «НЕТ СИЛ» + «!»; «КРИТИЧНО» при HP<25%; число HP `show_number=true`; фокус — каретка «>» + скобки |
| 5 | При «Без мигания» нет вспышек > 3 Гц | ✅ PASS | HP-крит не мигает; `FlashGovernor` пропускает 3/8 вспышек; `flame_multiplier=1.0`; свет зоны не мерцает; смерть без fade |
| 6 | RU/EN помещаются во все панели при 100/150% | ❌ **FAIL** | (а) WorldMap EN: текст кнопки зоны **144 > 141 px** при 100% и 150%; (б) UI 150% не применяется к HUD/инвентарю/диалогу и др. — шрифт HUD **8 → 8 px**; (в) смена языка на `Main` даёт `Invalid assignment ... Nil` в `DeathScreen._retranslate` (617–618), строки «МОНЕТЫ/ПРЕДМЕТЫ» не переводятся; (г) подсказка ability-gate в зоне 1 обрезана справа |
| 7 | Игра различима при яркости по умолчанию: герой отличим от фона | ✅ PASS (с оговоркой) | герой виден (тёмный силуэт + gold-оружие), режим «Читаемость силуэтов» включает 1-px контур и убирает виньетку (0.28 → 0.00). **Расхождение:** контур врагов не реализован, хотя DESIGN §9.1 говорит «у героя и врагов» |

Дополнительно проверено: `Config.no_flash` отключает мигание HP, мерцание света, fade смерти и печать текста; `Config.silhouette_readability` отключает виньетку и включает outline игрока.

---

## 3. NFR

Команда (нужен рендер):

```powershell
& $env:GODOT_PATH --path game res://tests/e2e/qa_nfr.tscn --quit-after 60000
```

Итог: **8/8 PASS**.

| Метрика | Требование | Замер | Статус |
|---|---|---|---|
| Старт до меню | ≤ 10 с | 59 мс (инициализация сцены после запуска движка) | ✅ |
| Загрузка зоны | ≤ 3 с | 0.441–0.826 с на переходах e2e; 0.056–0.127 с в повторном прогоне | ✅ |
| FPS в бою с 5 врагами | ≥ 60; p95 ≥ 55 | avg **723.9**, p50 **720**, p95 **720** (20 с, 13 969 кадров, vsync off) | ✅ |
| 20 циклов save/load | утечка ≤ 10% | static memory **57 922 363 → 57 926 379 байт (+0.01%)**, objects **3292 → 3292** | ✅ |
| 5 врагов в бою | — | враги **заспавнены QA-скриптом**: в собранных зонах их нет | ⚠️ оговорка |

Ограничения замера: 10-минутный FPS-прогон и 4-часовой soak не выполнялись; FPS-тест — 20 с, save/load — 20 циклов подряд. При этом запас по FPS и памяти многократный.

Наблюдение: headless-прогоны (GUT 518/518, e2e, a11y) завершаются с **exit code 1** и сообщениями `RID allocations ... leaked at exit` / `resources still in use at exit`. Во время игры падений нет; это риск для CI-шага «GUT headless», если CI проверяет код возврата.

---

## 4. Матрица трассируемости AC (SPEC §3)

| AC | Статус | Evidence |
|---|---|---|
| AC-01.1 движение | ✅ PASS | e2e: x `100 → 130` (клавиатура); input-probe: стик `100 → 134.6` |
| AC-01.2 прыжок H_jump ±1 px | ✅ PASS (GUT) | e2e базовый прыжок; точная высота — `test_player_movement` |
| AC-01.3 геймпад + ремап | ❌ FAIL | геймпад PASS (движение/прыжок); ремап из настроек недоступен (`Remap` не открывается) |
| AC-01.4 буфер ввода 150 мс | ✅ PASS (GUT) | `test_input_buffer` |
| AC-02.1 двойной прыжок | ❌ FAIL (интеграция) | логика PASS (GUT), получить способность негде |
| AC-02.2 dash + i-frames + C_dash≤1 с | ❌ FAIL (интеграция) | логика PASS (GUT); способность не получается |
| AC-02.3 wall slide/kick | ❌ FAIL (интеграция) | логика PASS (GUT); способность не получается |
| AC-02.4 gate блокирует и показывает подсказку | ❌ FAIL | блокировка PASS; подсказка обрезана справа (зона 1) |
| AC-03.1 урон/реакция ≤100 мс | ❌ FAIL (интеграция) | логика PASS (GUT `test_enemy_combat_e2e`); обычных врагов в мире нет |
| AC-03.2 блок/парирование | ✅ PASS (GUT) | `test_block_parry` |
| AC-03.3 stamina 0 → «НЕТ СИЛ» | ✅ PASS | a11y: бейдж «НЕТ СИЛ» + «!» |
| AC-03.4 фазы боссов + HUD | ✅ PASS | e2e: 5/5 боссов, события «ФАЗА II», бар босса |
| AC-04.1 способность открывает путь, T_load≤3 с | ❌ FAIL (интеграция) | переходы ≤0.83 с; dash/wall gates открываются после инъекции, но способности не получаются |
| AC-04.2 карта посещённых зон | ✅ PASS | `test_map`, a11y-навигация WorldMap; миникарта в HUD |
| AC-04.3 все gates после способности | ✅ PASS (при наличии способности) | e2e: dash-gate и wall-climb gate `open=true` |
| AC-05.1 сохранение/загрузка | ✅ PASS | слот 1 schema 6, `valid=true`; загрузка восстанавливает состояние |
| AC-05.2 смерть → экран → respawn, лут в corpse | ✅ PASS | e2e: 2 предмета + 42 монеты в corpse, respawn у костра |
| AC-05.3 corpse run | ✅ PASS | e2e: подбор вернул лут |
| AC-06.1 квест → репутация/NPC | ✅ PASS (частично) | `free 0 → 15`; выбор фракции и фракционная концовка недоступны |
| AC-06.2 доступ по репутации | ✅ PASS (GUT) | `test_factions`; UI фракций недостижим из игры |
| AC-07.1 палитра/читаемость героя | ✅ PASS (с оговоркой) | палитры зон совпадают с ZoneData; герой виден; outline есть только у героя |
| AC-07.2 кроссфейд музыки ≤2 с | ✅ PASS (GUT/код) | `test_audio`; на слух не проверялось (headless) |
| AC-08.1 прокачка у учителя | ❌ FAIL (интеграция) | логика PASS (GUT); ни одного Teacher в мире |
| AC-08.2 требования навыка/экипировки | ❌ FAIL (доступность UI) | логика PASS (GUT); учителя/экрана прокачки в игре нет |
| AC-09.1 FPS 5 врагов | ✅ PASS | p95 720 FPS (20 с, vsync off) |
| AC-09.2 20 save/load, память | ✅ PASS | +0.01%, objects 3292→3292 |
| EC-13 потеря фокуса окна | ❌ FAIL | `propagate_notification(FOCUS_OUT)` → `paused=false`, меню не открыто; обработчика в проекте нет |

---

## 5. Расхождения с SPEC/DESIGN

| # | Расхождение | Где |
|---|---|---|
| D1 | Нет точек получения способностей в мире | `game/world/props/ability_pickup.tscn` не инстанцируется ни в одной зоне; `Teacher` нигде не размещён |
| D2 | Нет обычных врагов/спавнеров | `EnemySpawner` есть как сцена, но не инстансируется в зонах |
| D3 | Арены боссов 1–4 прозрачны | `zone_01_village.tscn:161`, `zone_02_swamp.tscn:141`, `zone_03_mountains.tscn:156`, `zone_04_ruins.tscn:164` — `self_modulate = Color(1,1,1,0)` |
| D4 | Нет эмиттера выбора фракции | `EventBus.faction_choice_requested` есть (`autoload/EventBus.gd:83`), но `emit` только в тестах; `FactionChoice` не открывается |
| D5 | Ремап не подключён | `MainMenu.gd:761-763` (`_on_remap_requested(): pass`), `Settings.gd:161-169` (строка всегда disabled) |
| D6 | Journal/Factions не открываются из игры | нет InputMap-действий/вызовов; вкладки Inventory — disabled-заглушки (`Inventory.gd:1081-1093`) |
| D7 | A11y: DeathScreen ломается при смене языка | `DeathScreen.gd:617-618` пишет в `_coins_row_label`/`_items_row_label`, которые никогда не присваиваются (`_make_loss_row` возвращает `label`, но caller сохраняет только `value`) |
| D8 | A11y: WorldMap EN не влезает | кнопка зоны 144 px при доступных 141 px (100% и 150%) |
| D9 | A11y: UI 150% не масштабирует HUD и др. | `ui_scale` читают только `MainMenu`/`Settings`/`SaveSlots`; HUD 8 → 8 px |
| D10 | A11y: нет контура врагов в «Читаемость силуэтов» | `SilhouetteOutline` применяется только в `PlayerAnimation.gd` |
| D11 | AC-02.4: подсказка gate обрезается | `AbilityHint.gd:127-131` центрирует панель без clamp к 480 px; завал зоны 1 стоит на x=448 |
| D12 | EC-13 не реализован | нет обработки `NOTIFICATION_APPLICATION_FOCUS_OUT` |
| D13 | Headless exit code 1 из-за утечек | GUT 518/518, но `RID/resource leaked at exit`; риск красного CI |

---

## 6. Шаги воспроизведения

### B1. Способности не получаются

```powershell
cd game
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_probe.tscn
```

Ожидание: в зонах есть `AbilityPickup`/`Teacher`. Факт: у всех зон `pickups=[] teachers=[]`. Дополнительно:

```powershell
Select-String -Path game/**/*.tscn -Pattern 'ability_pickup|teacher.gd|Teacher'
```

совпадений в сценах зон нет.

### B2. Нет обычных врагов

Тот же `qa_probe`: у всех зон `enemies=[]`; `EnemySpawner` не инстансируется. Проверить в игре: зона 1 — на всей карте только NPC, костёр и босс.

### B3. Боссы 1–4 невидимы

1. Запустить игру, дойти до зоны 1 (или `qa_nfr.tscn`).
2. Переместить игрока в правую половину (`x≈360`).
3. Начать бой: HUD показывает «Пепельный Страж» и полосу HP, но на экране нет ни арены, ни босса.
4. В сцене: `BossArenaZone01.self_modulate = Color(1,1,1,0)`.

Скриншот: `...\Temp\opencode\qa_t37_boss_zone1.png`.

### B4. Выбор фракции и фракционная концовка

1. Зона 1 → хранитель → взять и сдать `quest_free_smuggle` (репутация `free` становится 15).
2. Пройти игру до финала.
3. Концовка — `ending_neutral`, экран выбора фракции не появлялся.
4. В коде: `EventBus.faction_choice_requested.emit` встречается только в `game/tests/`.

### B5. Ремап

1. Меню → Настройки → строка «Управление» — disabled, причина «T-24».
2. Нажать Enter/→ — экран `Remap.tscn` не открывается.
3. `MainMenu.gd:761` — `pass`.

### B6. Journal/Factions

1. В игре нажать `I` — открывается Inventory; вкладки «Карта/Журнал/Фракции» — серые подписи, не кнопки.
2. Отдельных клавиш/вызовов `Journal.open()`/`Factions.open()` в игровом коде нет.

### B7. A11y: DeathScreen при смене языка

```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_lang_probe.tscn
```

Факт:

```
SCRIPT ERROR: Invalid assignment of property or key 'text' with value of type 'String' on a base object of type 'Nil'.
   at: DeathScreen._retranslate (res://ui/death/DeathScreen.gd:617)
```

### B8. A11y: WorldMap EN / UI 150%

```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_a11y.tscn --quit-after 30000
```

Факты: `WorldMap/@Button: text 144 > 141` (EN, 100% и 150%); `масштаб UI 150% применяется к HUD — шрифт HUD 8 → 8 px` (FAIL).

### B9. AC-02.4: обрезанная подсказка

1. Зона 1, подойти к завалу справа (`x≈448`).
2. Подсказка «Нужно: ДВОЙНОЙ ПРЫЖОК» уходит за правый край 480 px: видно «Нужно: ДВОЙНО…».
3. Скриншот: `...\Temp\opencode\qa_t37_zone1.png`.

### B10. EC-13

```powershell
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_input_probe.tscn
```

Факт: `EC-13 paused=false menu=null` после `NOTIFICATION_APPLICATION_FOCUS_OUT`.

---

## 7. GUT-базлайн

```powershell
cd game
& $env:GODOT_PATH --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**GUT:** 518/518 (run 1), 517/518 (run 2); run 2 failed `test_long_boss_fight_stays_within_60hz_physics_budget` p95=0.01760 s > 0.01667 s - flaky/CI risk (targeted rerun: 11/11, p95=0.01430 s). Unit logic (FSM, abilities, combat, saves, UI) is covered, but this does not replace e2e: all blockers are integration.

---

## 8. Что нужно для повторной приёмки

- Разместить `AbilityPickup`/Teacher для double_jump/dash/wall_climb (или выдать их сюжетно) и проверить прохождение без QA-инъекции.
- Разместить `EnemySpawner`/врагов в зонах, чтобы бой и прокачка были игровым потоком.
- Убрать `self_modulate.a=0` у арен 1–4 (скрывать только фон арены, не `Boss`).
- Подключить `FactionChoice`/`Factions`/`Journal`/`Remap` к игровому вводу и сюжетному сигналу.
- Исправить `DeathScreen._retranslate` (присваивать row labels), WorldMap EN-переполнение, масштаб HUD/панелей и контур врагов.
- Добавить clamp подсказки `AbilityHint` к границам 480×270.
- Реализовать EC-13 (пауза + меню при потере фокуса).
- Повторить `qa_e2e.tscn`, `qa_a11y.tscn`, `qa_nfr.tscn` на новой ревизии; обновить SHA в этом отчёте.
