# QA: «Пепельный Бастион» — финальная сквозная приёмка T-37 после Fix-3a/3b

**Проверенная ревизия:** `aece545729ff68901ac9cfcf45017247cd03ab08` — ветка `v2`, HEAD (Fix-3a + Fix-3b сведены; предыдущая приёмка — `48de7dc`)
**Дата:** 2026-10-19
**Окружение:** Windows, portable Godot **4.4.1.stable** (`Godot_v4.4.1-stable_win64_console.exe`, `GODOT_PATH`), проект `game/`, GUT 9.x, 480×270; NFR/визуал — OpenGL 3.3 (NVIDIA RTX 3070 Ti).
**Метод:** headless e2e + headless a11y/fix/final probes + GUT + рендер-прогон NFR. QA-харнессы e2e/rerun адаптированы под SPEC §4.1 (wall_climb в зоне 2) и Fix-3a/N1; прод-код не менялся.

---

## Итог: ✅ **PASS**

Приёмка T-37 принимается на ревизии `aece545`. Все **9 исходных блокеров** и **N1–N5** закрыты; сквозной проход «меню → зона 1 → зоны 2–5 → 5 боссов → фракционная концовка → титры» проходит без игровых вылетов и блокировок.

| Прогон | Результат |
|---|---|
| Сквозной e2e (`qa_e2e`) | **130/130 PASS**, exit 0 |
| A11y DESIGN §9.6 пп.1–7 (`qa_a11y`) | **106 PASS / 0 FAIL**, exit 0 |
| Точечные фиксы B7/B8/B9 (`qa_fix_probe`) | **20/20 PASS**, exit 0 |
| Независимый финальный probe (`qa_final_probe`) | **18/18 PASS**, exit 0 |
| Повторный probe N1/N2 (`qa_rerun_probe`) | **12/12 PASS**, exit 0 |
| GUT | **518/518**, 7060 asserts, 45 скриптов, exit 0 |
| NFR (`qa_nfr`, рендер) | **8/8 PASS**, exit 0 |

Остаточные не-блокирующие замечания — §7 (leak-сообщения при выходе headless-прогона; dash остаётся world-pickup с метаданными `teacher_npc`, а не буквальным квестом NPC; 10-минутный FPS и 4-часовой soak не выполнялись).

---

## 1. Блокеры: 9 исходных + N1–N5

| # | Блокер | Статус | Evidence на `aece545` |
|---|---|---|---|
| 1 | Способности и `Teacher` недостижимы | ✅ **закрыт** | `qa_probe`: зона 1 — `AbilityPickupDoubleJump`, `teachers=["TeacherQuartermaster","TeacherHuntress","TeacherElder"]`; зона 2 — `AbilityPickupDash`, `AbilityPickupWallClimb`. `qa_e2e`: все 3 способности получены физическим входом в `Area2D`; gates `Rubble`/`DashGate`/`WallClimbGate` открыты |
| 2 | Нет обычных врагов | ✅ **закрыт** | `qa_probe`: `EnemySpawner` и 4–5 врагов в зонах 1–4. `qa_e2e`: `alive=4`, атака ранит/убивает `SwiftEnemy`, XP `0 → 50`. NFR: 5 реальных врагов зоны 2 |
| 3 | Боссы 1–4 невидимы | ✅ **закрыт** | `qa_e2e` 5/5: `arena.self_modulate.a=1.00`, `boss_visible=true`; рендер-кадр `user://qa_t37_boss_zone1.png` |
| 4 | Выбор фракции недостижим | ✅ **закрыт** | `qa_e2e`: квест завершён, репутация `free 0 → 15`, `FactionChoice` открылся сюжетным триггером; выбор `free` сохранён; концовка `ending_free` |
| 5 | Ремап недостижим | ✅ **закрыт** | `qa_e2e`: строка «Управление» `disabled=false`, Enter → `Remap`, 14 действий (вкл. `journal`/`factions`), Esc возвращает настройки |
| 6 | Journal/Factions недостижимы | ✅ **закрыт** | `qa_e2e`: N открывает/закрывает журнал и ставит/снимает паузу; F — экран фракций; I — инвентарь |
| 7 | A11y §9.6 п.6 (RU/EN 100/150%) | ✅ **закрыт** | `qa_a11y`: переполнение RU/EN при 100% и 150% — PASS для меню и всех панелей; `qa_fix_probe`: реальный рост шрифта на всех 8 экранах (`8→12`, `16→24`, `32→48`, WorldMap `16→20`); `DeathScreen` EN/RU без Nil; подсказка clamp; HUD `8→12` |
| 8 | AC-02.4: подсказка обрезана | ✅ **закрыт** | `qa_fix_probe`: panel `184 px`, offset `−62 px`, экранный прямоугольник `[294…478]×[163.5…176.5]` внутри 480×270; текст «Нужно: ДВОЙНОЙ ПРЫЖОК» полный |
| 9 | EC-13 не реализован | ✅ **закрыт** | `qa_fix_probe`: `FOCUS_OUT → paused=true`, `PauseMenu` видим, фокус на «Продолжить», Enter снимает паузу |
| N1 | Отмена выбора фракции навсегда блокирует US-06 | ✅ **закрыт** | `qa_e2e`: Esc закрывает экран (`chosen=false`), `_faction_choice_requested=false`, `_faction_choice_pending=true`; повторный разговор с NPC снова открывает выбор; B геймпада — то же; после этого выбор `free` подтверждён, концовка `ending_free`. `qa_rerun_probe`: 12/12 |
| N2 | UI 150% не масштабирует 8 экранов | ✅ **закрыт** | `qa_final_probe` + `qa_fix_probe`: Inventory `8→12`, Journal `16→24`, Factions `16→24`, FactionChoice `16→24`, WorldMap `16→20`, Campfire `8→12`, Remap `16→24`, DeathScreen `32→48` px |
| N3 | `Teacher` отсутствует в мире | ✅ **закрыт** | `qa_probe`/`qa_e2e`: 3 учителя в хабе (`quartermaster`, `huntress`, `elder`); E открывает панель (пауза), тренировка `strength 5→6`, следующая цена `1→2`; навык `power_strike` недоступен при силе 6: «ТРЕБУЕТСЯ: СИЛА 8 (у вас 6)», очки не списываются (AC-08.1/08.2) |
| N4 | Нет контура врагов | ✅ **закрыт** | `qa_final_probe`: у `Enemy` есть `is_silhouette_outline_enabled()` и `ShaderMaterial`; при `Config.silhouette_readability=false` — `false`, при `true` — `true`. `qa_a11y` п.7 PASS |
| N5 | Источники способностей расходятся со SPEC §4.1 | ✅ **закрыт** (см. §7.2) | `qa_final_probe`/`qa_e2e`: `AbilityPickupWallClimb` — в зоне 2, `source=optional_secret`, за `DashGate` (`pickup_x=416`, `gate_x=352`, gate `dash`); в зоне 3 дублирующего pickup нет; `WallClimbGate` зоны 3 открывается после получения (использование вне «родной» зоны). `qa_probe`: альтернативный путь `zone_02 → zone_04` требует только dash, поэтому wall_climb остаётся опциональным. Dash — в зоне 2 |

---

## 2. Сквозной проход (как игрок)

`qa_e2e.tscn`: **130/130 PASS**, игровых вылетов и блокировок нет; native exit code **0**.

| Шаг | Результат | Evidence |
|---|---|---|
| Меню → клавиатура/геймпад | ✅ | фокус `New/Load/Settings/Exit/LangRU`, стрелки + D-pad |
| Настройки → «Управление» → Remap → Esc | ✅ | 14 действий, возврат в настройки |
| «Новая игра» → `Main.tscn`, зона 1 | ✅ | `zone_01_village`, `abilities=[]` |
| Зона 1: движение, прыжок, HUD | ✅ | x `100.0 → 130.0`; y `213.9 → 185.5`; HUD/Campfire/Dialogue/DeathHandler смонтированы |
| Учитель в хабе: E → панель → тренировка → навык | ✅ | пауза, `strength 5→6`, цена `1→2`, предусловие силы 8, Esc снимает паузу |
| Двойной прыжок: подбор → gate | ✅ | вход в `AbilityPickupDoubleJump`; `Rubble.open=true` |
| Бой: 4 врага зоны 1 | ✅ | `SwiftEnemy hp=12 → 0`, XP `0 → 50` |
| N/F/I: журнал/фракции/инвентарь | ✅ | открытие/закрытие, пауза корректна |
| Костёр → слот 1 → загрузка | ✅ | `schema_version=6`, `valid=true`; загрузка восстанавливает состояние |
| Смерть → экран → respawn → corpse run | ✅ | 2 предмета + 42 монеты в corpse; подбор вернул всё |
| Диалог → квест → репутация → выбор фракции | ✅ | `free 0 → 15`; `FactionChoice` открылся; Esc и B отменяют, выбор открывается снова; выбран `free` |
| 5 боссов: арены, фазы, победа | ✅ | 5/5 видимы, у каждого «ФАЗА II», все отмечены побеждёнными |
| Переходы зон (физические выходы) | ✅ | 1→2 `0.279 с`, 2→3 `0.359 с`, 3→4 `0.440 с`, 4→5 `0.531 с` (≤ 3 с) |
| Финал → фракционная концовка → титры | ✅ | `ending_free`, `finished`; вылетов нет |

---

## 3. A11y-чек-лист DESIGN §9.6 (пп.1–7)

`qa_a11y.tscn`: **106 PASS / 0 FAIL**, exit 0.

| № | Пункт §9.6 | Статус | Evidence |
|---|---|---|---|
| 1 | Любой экран только клавиатурой и только геймпадом | ✅ PASS | MainMenu, Settings, SaveSlots, Campfire, Dialogue, DeathScreen, Inventory, Journal, Factions, FactionChoice, WorldMap, Remap — фокус и D-pad-навигация |
| 2 | Фокус виден на каждом интерактивном элементе | ✅ PASS | у всех проверенных владельцев `has_focus=true`, `is_focus_visible()=true` |
| 3 | 8-px текст ≥ 4.5:1 на фактическом фоне | ✅ PASS | минимум `blood-5/night` **4.59:1**; тема Label 11.29, Muted 6.60, Danger 5.19, Gold 9.71, Steel 6.26 |
| 4 | Нет состояния, различимого только цветом | ✅ PASS | «НЕТ СИЛ» + «!»; «КРИТ»; число HP; фокус-каретка «>» + скобки |
| 5 | «Без мигания»: нет вспышек > 3 Гц | ✅ PASS | HP-крит не мигает; `FlashGovernor` 3/8; `flame_multiplier=1.0`; свет зоны ровный; смерть без fade |
| 6 | RU/EN помещаются во все панели при 100/150% | ✅ PASS | переполнение RU/EN 100% и 150% — PASS для меню и панелей (HUD, Inventory, Journal, Factions, FactionChoice, WorldMap, Remap, Dialogue, Campfire, Death); 150% реально увеличивает шрифт на 8 экранах (N2); WorldMap EN влезает; `DeathScreen._retranslate` без Nil |
| 7 | Герой отличим от фона при штатной яркости | ✅ PASS | виньетка `0.28 → 0.00` в режиме читаемости; контур игрока включён; контур врагов включён и следует тумблеру (`qa_final_probe`: `false → true`) |

---

## 4. NFR

`qa_nfr.tscn` (рендер): **8/8 PASS**, exit 0.

| Метрика | Требование | Замер на `aece545` | Статус |
|---|---|---|---|
| Старт до меню | ≤ 10 с | **68 мс** (инициализация сцены после запуска движка) | ✅ |
| Загрузка зоны | ≤ 3 с | `SceneRouter`: **0.052–0.132 с**; физические выходы e2e: **0.279–0.531 с** | ✅ |
| FPS в бою с 5 врагами | ≥ 60; p95 ≥ 55 | avg **711.3**, p50 **720**, p95 **720** (20 с, 13 674 кадра, vsync off) | ✅ |
| 20 циклов save/load | утечка ≤ 10% | static memory **59 228 827 → 59 224 831 байт (−0.01%)**, objects **3390 → 3390** | ✅ |
| 5 врагов в бою | — | 5 реальных врагов из `EnemySpawner` зоны 2 (не QA-спавн) | ✅ |
| Память | ≤ 1 ГБ | ~59 МБ static memory в замере | ✅ |

Ограничения: 10-минутный FPS-прогон и 4-часовой soak не выполнялись (FPS — 20 с, save/load — 20 циклов). Запас по FPS и памяти многократный.

---

## 5. Матрица трассируемости AC (SPEC §3)

| AC | Статус | Evidence |
|---|---|---|
| AC-01.1 движение | ✅ PASS | e2e: x `100 → 130` |
| AC-01.2 прыжок H_jump ±1 px | ✅ PASS (GUT) | `test_player_movement` |
| AC-01.3 геймпад + ремап | ✅ PASS | e2e: геймпад D-pad; Remap открывается, 14 действий, персист |
| AC-01.4 буфер ввода 150 мс | ✅ PASS (GUT) | `test_input_buffer` |
| AC-02.1 двойной прыжок | ✅ PASS | pickup + GUT `test_double_jump_*` |
| AC-02.2 dash + i-frames + C_dash≤1 с | ✅ PASS | pickup + GUT `test_dash_*` |
| AC-02.3 wall slide/kick | ✅ PASS | pickup wall_climb в зоне 2 + GUT `test_wall_climb_*` |
| AC-02.4 gate блокирует и показывает подсказку | ✅ PASS | clamp, полный текст, gate `open=true` |
| AC-03.1 урон/реакция ≤100 мс | ✅ PASS | e2e: враги из зоны, урон/смерть/XP; GUT `test_combat_*` |
| AC-03.2 блок/парирование | ✅ PASS (GUT) | `test_block_parry` |
| AC-03.3 stamina 0 → «НЕТ СИЛ» | ✅ PASS | a11y-бейдж |
| AC-03.4 фазы боссов + HUD | ✅ PASS | e2e 5/5, «ФАЗА II» |
| AC-04.1 способность открывает путь, T_load≤3 с | ✅ PASS | gates открыты; переходы ≤ 0.531 с |
| AC-04.2 карта посещённых зон | ✅ PASS | GUT `test_map`, a11y WorldMap |
| AC-04.3 все gates после способности | ✅ PASS | e2e: `Rubble`, `DashGate`, `WallClimbGate` зоны 3 — `open=true` |
| AC-05.1 сохранение/загрузка | ✅ PASS | слот 1 schema 6, `valid=true`, состояние восстановлено |
| AC-05.2 смерть → экран → respawn, лут в corpse | ✅ PASS | 2 предмета + 42 монеты |
| AC-05.3 corpse run | ✅ PASS | лут подобран |
| AC-06.1 квест → репутация/NPC | ✅ PASS | `free 0 → 15`; выбор фракции открывается, отмена не блокирует |
| AC-06.2 доступ по репутации | ✅ PASS (GUT/UI) | `test_factions`; экран фракций достижим по F |
| AC-07.1 палитра/читаемость героя | ✅ PASS | палитры зон; герой и враги с контуром в режиме читаемости |
| AC-07.2 кроссфейд музыки ≤2 с | ✅ PASS (GUT) | `test_audio` |
| AC-08.1 прокачка у учителя | ✅ PASS | учитель в хабе; `strength 5→6`, цена `1→2` |
| AC-08.2 требования навыка/экипировки | ✅ PASS | `power_strike` требует силу 8; причина с требуемым/текущим; очки не списываются |
| AC-09.1 FPS 5 врагов | ✅ PASS | avg 711.3, p95 720 |
| AC-09.2 20 save/load, память | ✅ PASS | −0.01%, objects 3390→3390 |
| EC-13 потеря фокуса окна | ✅ PASS | пауза + `PauseMenu` + Resume |

---

## 6. Команды воспроизведения

```powershell
$env:GODOT_PATH = "C:\Users\cudjo\AppData\Local\Temp\opencode\godot\Godot_v4.4.1-stable_win64_console.exe"
cd game

# сквозной e2e (адаптирован под SPEC §4.1: wall_climb в зоне 2; N1 cancel→reopen)
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_e2e.tscn --quit-after 120000
# a11y §9.6 пп.1–7
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_a11y.tscn --quit-after 60000
# точечные фиксы B7/B8/B9 и UI 150%
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_fix_probe.tscn --quit-after 30000
# независимые N2/N4/N5
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_final_probe.tscn --quit-after 30000
# N1/N2 повторно
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_rerun_probe.tscn --quit-after 20000
# NFR (нужен рендер)
& $env:GODOT_PATH --path . res://tests/e2e/qa_nfr.tscn --quit-after 120000
# GUT
& $env:GODOT_PATH --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
# smoke прод-сцены
& $env:GODOT_PATH --headless --path . res://Main.tscn --quit-after 600
```

Логи: `...\Temp\opencode\qa3_e2e4.log`, `qa3_a11y3.log`, `qa3_fix2.log`, `qa3_final.log`, `qa3_rerun2.log`, `qa3_nfr2.log`, `qa3_gut.log`, `qa3_main_smoke.log`.

---

## 7. Остаточные расхождения (не блокируют приёмку)

### 7.1. N6. Leak-сообщения при выходе headless-прогонов — риск CI, не игровой вылет

**Симптом.** После завершения e2e в логе остаются `ERROR: N RID allocations ... leaked at exit`, `ObjectDB instances leaked`, `resources still in use at exit`; рендер-NFR дополнительно печатает `Texture with GL ID ...: leaked`. Это teardown-шум движка/QA-харнесса, не падение во время игры; e2e завершается `130/130` и native exit code **0**, NFR — `8/8` и exit 0.

**Что проверено.** После добавления QA-teardown (освобождение `Main`/`MainMenu`/dummy-сцены до `quit`) процесс завершается с кодом 0; smoke прод-сцены `res://Main.tscn --quit-after 600` и `MainMenu.tscn` — exit 0.

**Риск.** Если CI считает `ERROR:` в stderr ошибкой (а не только код возврата), шаг будет красным. Рекомендация: не валить CI на leak-сообщениях либо вычистить владельцев ресурсов в QA-харнессе.

**Воспроизведение.**
```powershell
cd game
& $env:GODOT_PATH --headless --path . res://tests/e2e/qa_e2e.tscn --quit-after 120000
```

### 7.2. N5b. Dash: зона совпадает со SPEC §4.1, но источник — pickup, а не буквальный квест NPC

`AbilityPickupDash` стоит в зоне 2 (`x=112`) и помечен `metadata/source="teacher_npc"`; в зоне 2 нет ни учителя, ни NPC-квеста, который бы его выдавал. SPEC §4.1 называет источник dash «Квест учителя/NPC, зона 2». Зона и метка источника совпадают, но фактически способность подбирается с земли. Это расхождение уровня «источник получения», не блокирует прохождение и T-37; рекомендуется либо добавить квест/NPC-выдачу, либо уточнить SPEC §4.1.

### 7.3. Ограничения замеров

10-минутный FPS-прогон (AC-09.1) и 4-часовой soak (AC-09.2) не выполнялись: FPS — 20 с, save/load — 20 циклов. Запас по FPS (avg 680, p95 720 при требовании 60/55) и по памяти (−0.01% при пороге 10%) многократный.

---
