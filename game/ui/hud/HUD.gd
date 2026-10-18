class_name AshenHUD
extends CanvasLayer
## AshenHUD — игровой HUD (T-19, PLAN §2.3: CanvasLayer 10, DESIGN §6.3).
##
## Состав (макет `docs/mockups/hud.html`, safe-зона 8 px):
##   * слева сверху — портрет, уровень (заглушка для T-29), HP сегментами +
##     число, критическое мигание 1 Гц и ступенчатая кайма по краю;
##   * выносливость — при 0 шкала пустая, значок «!» и подпись «НЕТ СИЛ»
##     (AC-03.3), мигание отключается `Config.no_flash` (DESIGN §9.3);
##   * три слота способностей: закрытая — замок + приглушённая иконка;
##     кулдаун — затемнённая полоса снизу (AC-02.2, контракт T-07);
##   * 4 быстрых слота (заглушки, контракт T-21), валюта и очки обучения
##     (поле-заглушка T-29);
##   * справа сверху — название зоны и миникарта `AshenMinimap` (T-33,
##     96x54, комнаты 8x6, тот же снимок, что у полной карты);
##   * контекстная подсказка ввода (`AshenPrompt` → глиф по
##     `InputManager.active_device`, EC-08);
##   * подсказка «Нужно: …» над препятствием (AC-02.4, контракт T-09);
##   * панель босса `AshenBossBar`: HP, метки 33/66 %, «ФАЗА II» (AC-03.4).
##
## Источник истины — `GameState` (`hp`, `stamina`, `abilities`, `currency`,
## `current_zone_id`), обновления — сигналы `EventBus`. HUD не хранит
## собственного геймплейного состояния: только визуальные заглушки полей,
## чьи системы ещё не реализованы (уровень/очки — T-29, кулдаун dash — T-07),
## и они описаны в контрактах ниже.
##
## Все цвета/размеры — `UITokens`, все панели/шкалы/слоты — компоненты T-18.
## Состояние дублируется не только цветом: числа HP, «НЕТ СИЛ» + «!»,
## «КРИТИЧНО», замок на закрытой способности, подписи фаз.
##
## Контракты заглушек:
##   * T-29 (прогрессия): `set_level(level)`, `set_training_points(points)`.
##     Когда в `GameState` появятся свойства `level`/`training_points`,
##     HUD подхватит их в `sync_from_game_state()` без правок HUD.
##   * T-33 (миникарта): `set_minimap_data(snapshot)` — внешний снимок
##     `WorldMapModel.build()`; неизвестные ключи игнорируются, падений нет.
##     Без внешнего вызова HUD сам синхронизирует миникарту из
##     `SceneRouter.visited_zone_ids` + `GameState.current_zone_id` + позиции
##     игрока и набора способностей (тот же снимок, что у `WorldMap`).
##   * T-07 (dash): `EventBus.ability_cooldown_changed(ability_id, remaining,
##     duration)` ИЛИ `hud.start_ability_cooldown(&"dash", c_dash)`;
##     `hud.set_ability_cooldown(...)` для ручной синхронизации.
##   * T-09 (ability gates): `EventBus.ability_hint_changed(ability_id,
##     required)` ИЛИ `hud.show_ability_hint(id)` / `hide_ability_hint()`.
##     При получении способности подсказка гаснет сама.
##   * T-21 (быстрые слоты): `set_quick_slot(index, item_id, count, icon)`.

const HUD_LAYER: int = 10
const QUICK_SLOT_COUNT: int = 4
const QUICK_SLOT_GAP: int = 5
const ABILITY_SLOT_GAP: int = 3
const ABILITY_IDS: Array[StringName] = [&"double_jump", &"dash", &"wall_climb"]
const ICON_PATTERNS: Dictionary = {
	&"double_jump": [
		"............",
		"..#......#..",
		".###....###.",
		"#####..#####",
		"..#......#..",
		"............",
		"..#......#..",
		".###....###.",
		"#####..#####",
		"..#......#..",
		"............",
		"............",
	],
	&"dash": [
		"............",
		"............",
		"....#.......",
		".....#......",
		"##########..",
		".....#......",
		"....#.......",
		"............",
		"..##...##...",
		"............",
		"............",
		"............",
	],
	&"wall_climb": [
		"............",
		"..##....##..",
		"..##....##..",
		"..########..",
		"..##....##..",
		"..##....##..",
		"..########..",
		"..##....##..",
		"..##....##..",
		"..########..",
		"..##....##..",
		"............",
	],
}
const ICON_COLORS: Dictionary = {
	&"double_jump": UITokens.GOLD_3,
	&"dash": UITokens.STEEL_3,
	&"wall_climb": UITokens.BONE,
}

const PORTRAIT_RECT := Rect2(8, 8, 28, 28)
const LEVEL_RECT := Rect2(8, 38, 36, 12)
const HP_POSITION := Vector2(44, 9)
const STAMINA_POSITION := Vector2(44, 23)
const CRITICAL_POSITION := Vector2(160, 9)
const NO_STAMINA_POSITION := Vector2(146, 23)
const ABILITY_ORIGIN := Vector2(44, 36)
const PROMPT_BOTTOM: int = 40
const BOSS_BOTTOM: int = 12
const BOSS_HEIGHT: float = 22.0

## Уровень героя — заглушка T-29.
var level: int = 1
## Очки обучения — заглушка T-29.
var training_points: int = 0

static var _icon_cache: Dictionary = {}

var _root: Control
var _portrait: AshenPanel
var _level_plate: _Plate
var _hp_bar: AshenBar
var _stamina_bar: AshenBar
var _critical_label: Label
var _critical_edge: _CriticalEdge
var _no_stamina: _NoStaminaBadge
var _ability_slots: Array[AshenSlot] = []
var _cooldown_strips: Dictionary = {}
var _quick_slots: Array[AshenSlot] = []
var _wallet: AshenPanel
var _currency_label: Label
var _points_label: Label
var _zone_label: Label
var _minimap_panel: AshenPanel
var _minimap: AshenMinimap
var _minimap_data: Dictionary = {}
var _minimap_override: bool = false
var _minimap_signature: String = ""
var _map_model: WorldMapModel
var _prompt_panel: AshenPanel
var _prompt: AshenPrompt
var _prompt_requested: bool = false
var _ability_hint_panel: AshenPanel
var _ability_hint_label: Label
var _ability_hint_ability: StringName = &""
var _boss_bar: AshenBossBar

var _cooldowns: Dictionary = {}
var _blink_time: float = 0.0
var _last_currency: int = 0
var _last_abilities: String = ""


func _init() -> void:
	name = "HUD"
	layer = HUD_LAYER


func _ready() -> void:
	layer = HUD_LAYER
	_build()
	_connect_event_bus()
	sync_from_game_state()
	_sync_minimap_data()


func _exit_tree() -> void:
	_disconnect_event_bus()


func _process(delta: float) -> void:
	advance_visuals(delta)


# ------------------------------------------------------------------------------
# Публичный API: визуальный тик
# ------------------------------------------------------------------------------

## Один шаг HUD-анимаций: кулдауны, уведомление босса, мигание крит. HP.
## Публичный, чтобы тесты не зависели от реальных кадров/таймеров.
func advance_visuals(delta: float) -> void:
	advance_cooldowns(delta)
	if _boss_bar != null:
		_boss_bar.advance(delta)
	_tick_critical_blink(delta)
	_poll_game_state()


# ------------------------------------------------------------------------------
# HP / выносливость (AC-03.3, DESIGN §6.3)
# ------------------------------------------------------------------------------

func set_health(current: float, maximum: float) -> void:
	_hp_bar.set_values(current, maximum)
	_refresh_critical()


func set_stamina(current: float, maximum: float) -> void:
	_stamina_bar.set_values(current, maximum)
	_no_stamina.visible = current <= 0.0


func is_critical() -> bool:
	return _hp_bar.is_critical()


func is_no_stamina_visible() -> bool:
	return _no_stamina.visible


func get_no_stamina_text() -> String:
	return _NoStaminaBadge.TEXT


## Мигание HP разрешено только вне режима «Без мигания» (DESIGN §9.3).
func is_critical_blinking() -> bool:
	return is_critical() and not _is_no_flash()


func _refresh_critical() -> void:
	var critical: bool = _hp_bar.is_critical()
	_critical_edge.visible = critical
	_critical_label.visible = critical
	if not critical:
		_blink_time = 0.0
		_hp_bar.modulate.a = 1.0
		_critical_label.modulate.a = 1.0


func _tick_critical_blink(delta: float) -> void:
	if not is_critical():
		return
	if _is_no_flash():
		# «Без мигания»: статичная кайма и рамка шкалы остаются (DESIGN §6.3).
		_blink_time = 0.0
		_hp_bar.modulate.a = 1.0
		_critical_label.modulate.a = 1.0
		return
	_blink_time += delta
	# 1 Гц, ступенями (steps(2)): не более 3 вспышек/с (a11y §9.3).
	var step: int = int(_blink_time * UITokens.BLINK_HZ * 2.0) % 2
	var alpha: float = 0.55 if step == 1 else 1.0
	_hp_bar.modulate.a = alpha
	_critical_label.modulate.a = alpha


func _is_no_flash() -> bool:
	var config: Node = _autoload("Config")
	return config != null and bool(config.get(&"no_flash"))


# ------------------------------------------------------------------------------
# Способности и кулдаун (AC-02.2, DESIGN §6.2/§6.3)
# ------------------------------------------------------------------------------

## Слот способности по id (`double_jump`/`dash`/`wall_climb`).
func get_ability_slot(ability_id: StringName) -> AshenSlot:
	var index: int = ABILITY_IDS.find(ability_id)
	return _ability_slots[index] if index >= 0 else null


func get_ability_slots() -> Array[AshenSlot]:
	var copy: Array[AshenSlot] = []
	copy.assign(_ability_slots)
	return copy


## Имя способности для слота/подсказки: реестр T-06, затем fallback HUD.
## T-33: тот же fallback использует карта (`WorldMapModel.ability_label`),
## чтобы подписи замков совпадали с HUD.
func ability_display_name(ability_id: StringName) -> String:
	return WorldMapModel.ability_label(ability_id)


func _refresh_abilities() -> void:
	for index: int in ABILITY_IDS.size():
		var ability_id: StringName = ABILITY_IDS[index]
		var slot: AshenSlot = _ability_slots[index]
		var owned: bool = GameState.has_ability(ability_id)
		slot.state = AshenSlot.State.NORMAL if owned else AshenSlot.State.UNAVAILABLE
		slot.item_icon = _ability_icon(ability_id)
		var display: String = ability_display_name(ability_id)
		slot.tooltip_text = display if owned else "Не открыто: %s" % display
	_last_abilities = _abilities_signature()
	_refresh_ability_hint_ownership()


## Запуск кулдауна способности (T-07 может звать напрямую).
func start_ability_cooldown(ability_id: StringName, duration: float) -> void:
	set_ability_cooldown(ability_id, duration, duration)


## Прямая установка кулдауна (остаток/длительность в секундах).
func set_ability_cooldown(ability_id: StringName, remaining: float, duration: float) -> void:
	if ability_id == &"":
		return
	if duration <= 0.0 or remaining <= 0.0:
		_cooldowns.erase(ability_id)
	else:
		_cooldowns[ability_id] = {
			"remaining": clampf(remaining, 0.0, duration),
			"duration": duration,
		}
	_refresh_cooldown_visuals()


func advance_cooldowns(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for ability_id: StringName in _cooldowns.keys():
		var entry: Dictionary = _cooldowns[ability_id]
		entry["remaining"] = maxf(float(entry["remaining"]) - delta, 0.0)
		if float(entry["remaining"]) <= 0.0:
			_cooldowns.erase(ability_id)
	_refresh_cooldown_visuals()


func is_cooldown_active(ability_id: StringName) -> bool:
	return _cooldowns.has(ability_id)


## Остаток кулдауна 0…1 (1 — только запущен, 0 — готово).
func get_cooldown_ratio(ability_id: StringName) -> float:
	if not _cooldowns.has(ability_id):
		return 0.0
	var entry: Dictionary = _cooldowns[ability_id]
	var duration: float = maxf(float(entry["duration"]), 0.0001)
	return clampf(float(entry["remaining"]) / duration, 0.0, 1.0)


func get_cooldown_strip(ability_id: StringName) -> Control:
	return _cooldown_strips.get(ability_id) as Control


func _refresh_cooldown_visuals() -> void:
	for ability_id: StringName in _cooldown_strips.keys():
		var strip: _CooldownStrip = _cooldown_strips[ability_id]
		strip.ratio = get_cooldown_ratio(ability_id)
		strip.visible = is_cooldown_active(ability_id)
		strip.queue_redraw()


func _on_bus_ability_cooldown_changed(
	ability_id: StringName,
	remaining: float,
	duration: float
) -> void:
	set_ability_cooldown(ability_id, remaining, duration)


## Иконка способности: пиксельный паттерн из токенов (арт T-05 заменит позже).
func _ability_icon(ability_id: StringName) -> Texture2D:
	if _icon_cache.has(ability_id):
		return _icon_cache[ability_id] as Texture2D
	var pattern: Array = ICON_PATTERNS.get(ability_id, [])
	if pattern.is_empty():
		return null
	var image := Image.create(UITokens.ICON, UITokens.ICON, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var color: Color = ICON_COLORS.get(ability_id, UITokens.STONE_5)
	for y: int in pattern.size():
		var row: String = pattern[y]
		for x: int in mini(row.length(), UITokens.ICON):
			if row[x] == "#":
				image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[ability_id] = texture
	return texture


# ------------------------------------------------------------------------------
# Быстрые слоты (заглушки T-21)
# ------------------------------------------------------------------------------

func get_quick_slot(index: int) -> AshenSlot:
	if index < 0 or index >= _quick_slots.size():
		return null
	return _quick_slots[index]


func get_quick_slots() -> Array[AshenSlot]:
	var copy: Array[AshenSlot] = []
	copy.assign(_quick_slots)
	return copy


## Заполнить быстрый слот (T-21). Пустой id — слот снова «пуст».
func set_quick_slot(
	index: int,
	item_id: StringName,
	count: int = 0,
	icon: Texture2D = null
) -> bool:
	var slot: AshenSlot = get_quick_slot(index)
	if slot == null:
		return false
	if item_id == &"":
		slot.state = AshenSlot.State.EMPTY
		slot.count = -1
		slot.item_icon = null
		return true
	slot.state = AshenSlot.State.NORMAL
	slot.item_icon = icon
	slot.count = maxi(count, 0)
	return true


# ------------------------------------------------------------------------------
# Валюта, очки обучения, уровень (T-29)
# ------------------------------------------------------------------------------

func get_currency_text() -> String:
	return _currency_label.text


func get_training_points_text() -> String:
	return _points_label.text


func get_level_text() -> String:
	return _level_plate.text


func set_level(new_level: int) -> void:
	level = maxi(new_level, 1)
	_level_plate.text = "УР%d" % level
	_level_plate.queue_redraw()


func set_training_points(points: int) -> void:
	training_points = maxi(points, 0)
	_points_label.text = "ОП %d" % training_points
	_points_label.tooltip_text = "Очки обучения: %d" % training_points


func _update_currency() -> void:
	_last_currency = maxi(GameState.currency, 0)
	_currency_label.text = format_number(_last_currency)
	_currency_label.tooltip_text = "Монеты: %d" % _last_currency


static func format_number(value_value: int) -> String:
	var text: String = str(maxi(value_value, 0))
	var result: String = ""
	var count: int = 0
	for index: int in range(text.length() - 1, -1, -1):
		result = text[index] + result
		count += 1
		if count % 3 == 0 and index > 0:
			result = " " + result
	return result


# ------------------------------------------------------------------------------
# Зона и мини-карта (T-33)
# ------------------------------------------------------------------------------

func get_zone_text() -> String:
	return _zone_label.text


func get_minimap() -> Control:
	return _minimap


func get_minimap_panel() -> AshenPanel:
	return _minimap_panel


## Внешний снимок миникарты (T-33). Неизвестные/битые поля игнорируются.
## Пустой словарь снимает внешний override: HUD снова рисует реальную карту.
func set_minimap_data(data: Dictionary) -> void:
	_minimap_data = data.duplicate(true)
	_minimap_override = not data.is_empty()
	_minimap.set_data(_minimap_data)
	_minimap_signature = ""


func get_minimap_data() -> Dictionary:
	return _minimap_data.duplicate(true)


## Автосинхронизация миникарты с полной картой: один и тот же снимок модели.
func _sync_minimap_data() -> void:
	if _minimap_override:
		return
	var snapshot: Dictionary = _build_minimap_snapshot()
	var signature: String = _minimap_snapshot_signature(snapshot)
	if signature == _minimap_signature:
		return
	_minimap_signature = signature
	_minimap_data = snapshot
	_minimap.set_data(snapshot)


func _build_minimap_snapshot() -> Dictionary:
	var visited: Array[StringName] = []
	if SceneRouter.has_method(&"get_visited_zone_ids"):
		var stored: Variant = SceneRouter.get_visited_zone_ids()
		if stored is Array:
			for value: Variant in stored:
				visited.append(StringName(str(value)))
	var current_zone: StringName = GameState.current_zone_id
	if current_zone == &"" and SceneRouter.has_method(&"get"):
		var router_zone: Variant = SceneRouter.get(&"current_zone_id")
		if router_zone is StringName:
			current_zone = router_zone
	var player_position: Vector2 = _player_position(current_zone)
	return _map_model_instance().build(
		visited,
		current_zone,
		player_position,
		GameState.get_abilities()
	)


func _map_model_instance() -> WorldMapModel:
	if _map_model == null:
		_map_model = WorldMapModel.new()
		_map_model.reload()
	return _map_model


## Позиция игрока в текущей зоне; без игрока — центр комнаты (метка видна).
func _player_position(zone_id: StringName) -> Vector2:
	var tree := get_tree()
	if tree != null:
		var player := tree.get_first_node_in_group(&"player") as Node2D
		if player != null and is_instance_valid(player):
			return player.global_position
	var data: ZoneData = _map_model_instance().get_zone(zone_id)
	var room: ZoneRoom = WorldMapModel.first_room(data)
	if room != null:
		return room.world_rect.get_center()
	return Vector2.ZERO


func _minimap_snapshot_signature(snapshot: Dictionary) -> String:
	var visited: Array = snapshot.get("visited_zone_ids", [])
	var visited_text := PackedStringArray()
	for value: Variant in visited:
		visited_text.append(str(value))
	var player: Dictionary = snapshot.get("player", {})
	var abilities := PackedStringArray()
	for ability_id: StringName in GameState.get_abilities():
		abilities.append(String(ability_id))
	return "%s|%s|%s|%s|%s|%s" % [
		",".join(visited_text),
		str(snapshot.get("current_zone_id", "")),
		str(player.get("cell", Vector2i(-1, -1))),
		str(player.get("local", Vector2.ZERO)),
		",".join(abilities),
		str(snapshot.get("bonfires", []).size()),
	]


func _set_zone(zone_id: StringName, display_name: String) -> void:
	if display_name.is_empty():
		_zone_label.text = String(zone_id)
	else:
		_zone_label.text = display_name


func _update_zone_from_state() -> void:
	if GameState.current_zone_id == &"":
		return
	var zone_id: String = String(GameState.current_zone_id)
	var path: String = "res://data/zones/%s.tres" % zone_id
	if not ResourceLoader.exists(path):
		return
	var data: Variant = load(path)
	if data == null:
		return
	var name_value: Variant = data.get(&"display_name")
	if name_value is String and not (name_value as String).is_empty():
		_set_zone(GameState.current_zone_id, name_value as String)


# ------------------------------------------------------------------------------
# Контекстная подсказка ввода (EC-08)
# ------------------------------------------------------------------------------

## Показать подсказку: действие InputMap + текст. Глиф выбирает AshenPrompt
## по `InputManager.active_device` (клавиатура/Xbox/PlayStation).
func set_prompt(action: StringName, text: String) -> void:
	_prompt_requested = true
	_prompt.setup(action, text)
	_apply_prompt_visibility()
	_fit_prompt()


func hide_prompt() -> void:
	_prompt_requested = false
	_apply_prompt_visibility()


func is_prompt_visible() -> bool:
	return _prompt_panel != null and _prompt_panel.visible


func get_prompt() -> AshenPrompt:
	return _prompt


func get_prompt_text() -> String:
	return _prompt.get_text()


func _apply_prompt_visibility() -> void:
	var in_boss_fight: bool = _boss_bar != null and _boss_bar.is_fight_visible()
	_prompt_panel.visible = _prompt_requested and not in_boss_fight


func _fit_prompt() -> void:
	if _prompt_panel == null:
		return
	var min_size: Vector2 = _prompt_panel.get_combined_minimum_size()
	_prompt_panel.offset_left = -min_size.x * 0.5
	_prompt_panel.offset_right = min_size.x * 0.5
	_prompt_panel.offset_top = -float(PROMPT_BOTTOM) - min_size.y
	_prompt_panel.offset_bottom = -float(PROMPT_BOTTOM)


# ------------------------------------------------------------------------------
# Подсказка «Нужно: …» над препятствием (AC-02.4, контракт T-09)
# ------------------------------------------------------------------------------

func show_ability_hint(ability_id: StringName) -> void:
	if ability_id == &"":
		return
	if GameState.has_ability(ability_id):
		hide_ability_hint()
		return
	_ability_hint_ability = ability_id
	_ability_hint_label.text = ability_display_name(ability_id)
	_ability_hint_panel.visible = true


func hide_ability_hint() -> void:
	_ability_hint_ability = &""
	if _ability_hint_panel != null:
		_ability_hint_panel.visible = false


func is_ability_hint_visible() -> bool:
	return _ability_hint_panel != null and _ability_hint_panel.visible


func get_ability_hint_text() -> String:
	return _ability_hint_label.text if _ability_hint_label != null else ""


func get_ability_hint_panel() -> AshenPanel:
	return _ability_hint_panel


func _refresh_ability_hint_ownership() -> void:
	if _ability_hint_ability != &"" and GameState.has_ability(_ability_hint_ability):
		hide_ability_hint()


func _on_bus_ability_hint_changed(ability_id: StringName, required: bool) -> void:
	if required:
		show_ability_hint(ability_id)
	elif _ability_hint_ability == ability_id or ability_id == &"":
		hide_ability_hint()


# ------------------------------------------------------------------------------
# Панель босса (AC-03.4)
# ------------------------------------------------------------------------------

func get_boss_bar() -> AshenBossBar:
	return _boss_bar


func is_boss_visible() -> bool:
	return _boss_bar != null and _boss_bar.is_fight_visible()


func _on_boss_fight_started(
	boss_id: StringName,
	display_name: String,
	max_hp: float,
	phase_thresholds: PackedFloat32Array
) -> void:
	_boss_bar.begin_fight(boss_id, display_name, max_hp, phase_thresholds)
	_apply_prompt_visibility()


func _on_boss_health_changed(boss_id: StringName, current: float, maximum: float) -> void:
	if _boss_bar.boss_id == boss_id:
		_boss_bar.set_health(current, maximum)


func _on_boss_phase_changed(boss_id: StringName, phase_index: int, phase_title: String) -> void:
	if _boss_bar.boss_id == boss_id:
		_boss_bar.set_phase(phase_index, phase_title)


func _on_boss_defeated(boss_id: StringName, _zone_id: StringName, _at_position: Vector2) -> void:
	if _boss_bar.boss_id == boss_id:
		_boss_bar.end_fight()
		_apply_prompt_visibility()


# ------------------------------------------------------------------------------
# Синхронизация с GameState
# ------------------------------------------------------------------------------

## Полный снимок состояния (ready, загрузка сейва, возрождение).
func sync_from_game_state() -> void:
	var maximum_hp: float = maxf(GameState.hp_max, 1.0)
	set_health(GameState.hp, maximum_hp)
	set_stamina(GameState.stamina, maxf(GameState.stamina_max, 1.0))
	_refresh_abilities()
	_update_currency()
	_update_zone_from_state()
	_sync_progression_fields()
	_sync_minimap_data()


## Поля T-29: пока свойств нет в GameState — остаются значения-заглушки.
func _sync_progression_fields() -> void:
	var level_value: Variant = GameState.get(&"level")
	if level_value is int and int(level_value) > 0 and int(level_value) != level:
		set_level(int(level_value))
	var points_value: Variant = GameState.get(&"training_points")
	if points_value is int and int(points_value) != training_points:
		set_training_points(int(points_value))


func _poll_game_state() -> void:
	if GameState.currency != _last_currency:
		_update_currency()
	_sync_progression_fields()
	var signature: String = _abilities_signature()
	if signature != _last_abilities:
		_refresh_abilities()
		sync_from_game_state()
	_sync_minimap_data()


func _abilities_signature() -> String:
	var parts := PackedStringArray()
	for ability_id: StringName in GameState.get_abilities():
		parts.append(String(ability_id))
	return ",".join(parts)


# ------------------------------------------------------------------------------
# Сигналы
# ------------------------------------------------------------------------------

func _connect_event_bus() -> void:
	_connect_signal(EventBus.player_health_changed, _on_player_health_changed)
	_connect_signal(EventBus.stamina_changed, _on_stamina_changed)
	_connect_signal(EventBus.ability_acquired, _on_ability_acquired)
	_connect_signal(EventBus.zone_entered, _on_zone_entered)
	_connect_signal(EventBus.boss_fight_started, _on_boss_fight_started)
	_connect_signal(EventBus.boss_health_changed, _on_boss_health_changed)
	_connect_signal(EventBus.boss_phase_changed, _on_boss_phase_changed)
	_connect_signal(EventBus.boss_defeated, _on_boss_defeated)
	_connect_signal(EventBus.boss_reward_granted, _on_boss_reward_granted)
	_connect_signal(EventBus.save_loaded, _on_save_loaded)
	_connect_signal(EventBus.player_respawned, _on_player_respawned)
	_connect_signal(EventBus.checkpoint_activated, _on_checkpoint_activated)
	# Контракты T-07/T-09: подключаемся, если сигналы уже объявлены в EventBus.
	if EventBus.has_signal(&"ability_cooldown_changed"):
		if not EventBus.is_connected(
			&"ability_cooldown_changed",
			_on_bus_ability_cooldown_changed
		):
			EventBus.connect(&"ability_cooldown_changed", _on_bus_ability_cooldown_changed)
	if EventBus.has_signal(&"ability_hint_changed"):
		if not EventBus.is_connected(&"ability_hint_changed", _on_bus_ability_hint_changed):
			EventBus.connect(&"ability_hint_changed", _on_bus_ability_hint_changed)


func _disconnect_event_bus() -> void:
	_disconnect_signal(EventBus.player_health_changed, _on_player_health_changed)
	_disconnect_signal(EventBus.stamina_changed, _on_stamina_changed)
	_disconnect_signal(EventBus.ability_acquired, _on_ability_acquired)
	_disconnect_signal(EventBus.zone_entered, _on_zone_entered)
	_disconnect_signal(EventBus.boss_fight_started, _on_boss_fight_started)
	_disconnect_signal(EventBus.boss_health_changed, _on_boss_health_changed)
	_disconnect_signal(EventBus.boss_phase_changed, _on_boss_phase_changed)
	_disconnect_signal(EventBus.boss_defeated, _on_boss_defeated)
	_disconnect_signal(EventBus.boss_reward_granted, _on_boss_reward_granted)
	_disconnect_signal(EventBus.save_loaded, _on_save_loaded)
	_disconnect_signal(EventBus.player_respawned, _on_player_respawned)
	_disconnect_signal(EventBus.checkpoint_activated, _on_checkpoint_activated)
	if EventBus.has_signal(&"ability_cooldown_changed"):
		if EventBus.is_connected(
			&"ability_cooldown_changed",
			_on_bus_ability_cooldown_changed
		):
			EventBus.disconnect(&"ability_cooldown_changed", _on_bus_ability_cooldown_changed)
	if EventBus.has_signal(&"ability_hint_changed"):
		if EventBus.is_connected(&"ability_hint_changed", _on_bus_ability_hint_changed):
			EventBus.disconnect(&"ability_hint_changed", _on_bus_ability_hint_changed)


func _connect_signal(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback)


func _disconnect_signal(sig: Signal, callback: Callable) -> void:
	if sig.is_connected(callback):
		sig.disconnect(callback)


func _on_player_health_changed(current: float, maximum: float) -> void:
	set_health(current, maximum)


func _on_stamina_changed(current: float, maximum: float) -> void:
	set_stamina(current, maximum)


func _on_ability_acquired(_ability_id: StringName) -> void:
	_refresh_abilities()
	_minimap_override = false
	_sync_minimap_data()


func _on_zone_entered(zone_id: StringName, display_name: String) -> void:
	_set_zone(zone_id, display_name)
	_boss_bar.end_fight()
	_apply_prompt_visibility()
	_minimap_override = false
	_sync_minimap_data()


func _on_checkpoint_activated(_zone_id: StringName, _bonfire_id: StringName) -> void:
	_minimap_override = false
	_sync_minimap_data()


func _on_boss_reward_granted(_boss_id: StringName, _reward_id: StringName, _gold: int) -> void:
	_update_currency()


func _on_save_loaded(_slot: int) -> void:
	sync_from_game_state()


func _on_player_respawned(_zone_id: StringName, _position: Vector2) -> void:
	sync_from_game_state()


# ------------------------------------------------------------------------------
# Построение
# ------------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.resized.connect(_on_root_resized)
	add_child(_root)

	# Кайма критического HP — декоративная, по краю экрана (как в макете).
	_critical_edge = _CriticalEdge.new()
	_critical_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_critical_edge.visible = false
	_root.add_child(_critical_edge)

	_build_player_block()
	_build_top_right()
	_build_quick_slots()
	_build_wallet()
	_build_prompt()
	_build_ability_hint()
	_build_boss_bar()

	set_level(level)
	set_training_points(training_points)
	_refresh_critical()


func _build_player_block() -> void:
	_portrait = AshenPanel.new()
	_portrait.variant = UIStyle.PanelVariant.SOLID
	_portrait.padding = 0
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_at(_portrait, PORTRAIT_RECT)
	var face := _PortraitFace.new()
	_portrait.add_child(face)

	_level_plate = _Plate.new()
	_level_plate.text = "УР1"
	_add_at(_level_plate, LEVEL_RECT)
	_level_plate.queue_redraw()

	_hp_bar = AshenBar.new()
	_hp_bar.kind = AshenBar.Kind.HP
	_hp_bar.position = HP_POSITION
	_hp_bar.size = UITokens.BAR_HP_SIZE
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hp_bar)

	_stamina_bar = AshenBar.new()
	_stamina_bar.kind = AshenBar.Kind.STAMINA
	_stamina_bar.position = STAMINA_POSITION
	_stamina_bar.size = UITokens.BAR_STAMINA_SIZE
	_stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stamina_bar)

	_critical_label = _make_label("КРИТИЧНО", UITokens.BLOOD_5)
	_critical_label.position = CRITICAL_POSITION
	_critical_label.size = Vector2(72, 10)
	_critical_label.visible = false
	_root.add_child(_critical_label)

	_no_stamina = _NoStaminaBadge.new()
	_no_stamina.position = NO_STAMINA_POSITION
	_no_stamina.size = _NoStaminaBadge.SIZE
	_no_stamina.visible = false
	_root.add_child(_no_stamina)

	for index: int in ABILITY_IDS.size():
		var slot := AshenSlot.new()
		slot.slot_size = UITokens.SLOT_HUD
		slot.position = ABILITY_ORIGIN + Vector2(
			float(index * (UITokens.SLOT_HUD + ABILITY_SLOT_GAP)),
			0.0
		)
		slot.size = Vector2(UITokens.SLOT_HUD, UITokens.SLOT_HUD)
		slot.state = AshenSlot.State.UNAVAILABLE
		slot.focus_mode = Control.FOCUS_NONE
		_root.add_child(slot)
		_ability_slots.append(slot)

		var strip := _CooldownStrip.new()
		strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		strip.visible = false
		slot.add_child(strip)
		_cooldown_strips[ABILITY_IDS[index]] = strip


func _build_top_right() -> void:
	_minimap_panel = AshenPanel.new()
	_minimap_panel.variant = UIStyle.PanelVariant.GLASS
	_minimap_panel.padding = UITokens.SP_1 + 1
	_minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var minimap_size := UITokens.MINIMAP_SIZE + Vector2(
		float((UIStyle.PANEL_MARGIN + UITokens.SP_1 + 1) * 2),
		float((UIStyle.PANEL_MARGIN + UITokens.SP_1 + 1) * 2)
	)
	_add_top_right(
		_minimap_panel,
		UITokens.SAFE_MARGIN,
		UITokens.SAFE_MARGIN,
		int(minimap_size.x),
		int(minimap_size.y)
	)
	_minimap = AshenMinimap.new()
	_minimap_panel.add_child(_minimap)

	_zone_label = _make_label("", UITokens.STONE_5, HORIZONTAL_ALIGNMENT_RIGHT)
	_add_top_right(
		_zone_label,
		UITokens.SAFE_MARGIN,
		UITokens.SAFE_MARGIN + int(minimap_size.y) + UITokens.SP_1,
		140,
		10
	)


func _build_quick_slots() -> void:
	for index: int in QUICK_SLOT_COUNT:
		var slot := AshenSlot.new()
		slot.slot_size = UITokens.SLOT_HUD
		slot.state = AshenSlot.State.EMPTY
		slot.key_hint = str(index + 1)
		slot.focus_mode = Control.FOCUS_NONE
		_add_bottom_left(
			slot,
			UITokens.SAFE_MARGIN + index * (UITokens.SLOT_HUD + QUICK_SLOT_GAP),
			UITokens.SAFE_MARGIN,
			UITokens.SLOT_HUD,
			UITokens.SLOT_HUD
		)
		_quick_slots.append(slot)


func _build_wallet() -> void:
	_wallet = AshenPanel.new()
	_wallet.variant = UIStyle.PanelVariant.GLASS
	_wallet.padding = UITokens.SP_2
	_wallet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_bottom_right(_wallet, UITokens.SAFE_MARGIN, UITokens.SAFE_MARGIN, 96, 44)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UITokens.SP_1)
	column.custom_minimum_size = Vector2(74, 22)
	_wallet.add_child(column)

	var currency_row := _make_wallet_row(_WalletIcon.Kind.COIN)
	_currency_label = currency_row.get_child(1) as Label
	column.add_child(currency_row)

	var points_row := _make_wallet_row(_WalletIcon.Kind.SCROLL)
	_points_label = points_row.get_child(1) as Label
	column.add_child(points_row)


func _make_wallet_row(kind: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UITokens.SP_2)
	row.custom_minimum_size = Vector2(74, 10)

	var icon := _WalletIcon.new()
	icon.kind = kind
	row.add_child(icon)

	var value := _make_label("", UITokens.BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.custom_minimum_size = Vector2(60, 10)
	row.add_child(value)
	return row


func _build_prompt() -> void:
	_prompt_panel = AshenPanel.new()
	_prompt_panel.variant = UIStyle.PanelVariant.GLASS
	_prompt_panel.padding = UITokens.SP_2
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, false)
	_prompt_panel.visible = false
	_root.add_child(_prompt_panel)

	_prompt = AshenPrompt.new()
	_prompt_panel.add_child(_prompt)
	_prompt.setup(&"interact", "")
	_prompt.minimum_size_changed.connect(_fit_prompt)
	_fit_prompt()


func _build_ability_hint() -> void:
	_ability_hint_panel = AshenPanel.new()
	_ability_hint_panel.variant = UIStyle.PanelVariant.SOLID
	_ability_hint_panel.padding = UITokens.SP_2
	_ability_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_top_right(
		_ability_hint_panel,
		UITokens.SAFE_MARGIN,
		132,
		128,
		48
	)
	_ability_hint_panel.visible = false

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", UITokens.SP_1)
	column.custom_minimum_size = Vector2(108, 0)
	_ability_hint_panel.add_child(column)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", UITokens.SP_2)
	column.add_child(header)

	var lock := _LockIcon.new()
	header.add_child(lock)

	var need := _make_label("Нужно:", UITokens.STONE_5)
	header.add_child(need)

	_ability_hint_label = _make_label("", UITokens.GOLD_3)
	_ability_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ability_hint_label.custom_minimum_size = Vector2(108, 16)
	column.add_child(_ability_hint_label)


func _build_boss_bar() -> void:
	_boss_bar = AshenBossBar.new()
	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM, false)
	_boss_bar.offset_left = -UITokens.BAR_BOSS_SIZE.x * 0.5
	_boss_bar.offset_right = UITokens.BAR_BOSS_SIZE.x * 0.5
	_boss_bar.offset_top = -float(BOSS_BOTTOM) - BOSS_HEIGHT
	_boss_bar.offset_bottom = -float(BOSS_BOTTOM)
	_root.add_child(_boss_bar)


func _on_root_resized() -> void:
	_fit_prompt()


func _add_at(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	control.position = rect.position
	control.size = rect.size
	_root.add_child(control)


func _add_top_right(control: Control, margin: int, top: int, width: int, height: int) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_RIGHT, false)
	control.offset_left = -float(margin + width)
	control.offset_right = -float(margin)
	control.offset_top = float(top)
	control.offset_bottom = float(top + height)
	_root.add_child(control)


func _add_bottom_left(
	control: Control,
	left: int,
	bottom: int,
	width: int,
	height: int
) -> void:
	control.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, false)
	control.offset_left = float(left)
	control.offset_right = float(left + width)
	control.offset_top = -float(bottom + height)
	control.offset_bottom = -float(bottom)
	_root.add_child(control)


func _add_bottom_right(
	control: Control,
	margin: int,
	bottom: int,
	width: int,
	height: int
) -> void:
	control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT, false)
	control.offset_left = -float(margin + width)
	control.offset_right = -float(margin)
	control.offset_top = -float(bottom + height)
	control.offset_bottom = -float(bottom)
	_root.add_child(control)


func _make_label(
	text: String,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIStyle.font())
	label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
	label.add_theme_color_override("font_color", color)
	# Тень void 1 px — 8-px текст читается поверх сцены (DESIGN §9.1).
	label.add_theme_color_override("font_shadow_color", UITokens.VOID)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _autoload(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)


# ------------------------------------------------------------------------------
# Геттеры для тестов/QA
# ------------------------------------------------------------------------------

func get_root_control() -> Control:
	return _root


func get_portrait() -> Control:
	return _portrait


func get_level_plate() -> Control:
	return _level_plate


func get_hp_bar() -> AshenBar:
	return _hp_bar


func get_stamina_bar() -> AshenBar:
	return _stamina_bar


func get_critical_label() -> Label:
	return _critical_label


func get_critical_edge() -> Control:
	return _critical_edge


func get_no_stamina_badge() -> Control:
	return _no_stamina


func get_wallet() -> AshenPanel:
	return _wallet


func get_zone_label() -> Label:
	return _zone_label


func get_prompt_panel() -> Control:
	return _prompt_panel


# ------------------------------------------------------------------------------
# Внутренние элементы отрисовки (держат HUD-специфичные пиксели в токенах)
# ------------------------------------------------------------------------------

## Мелкая табличка (уровень): 9-slice AshenPanel для 12 px слишком велик,
## поэтому рамка/текст рисуются теми же примитивами UIStyle.
class _Plate extends Control:

	var text: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, UITokens.NIGHT_9)
		UIStyle.draw_frame(self, rect, UITokens.BORDER_INNER, UITokens.STONE_3)
		var baseline: float = (
			(size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
			+ UIStyle.baseline_y(UITokens.FONT_BODY)
		)
		UIStyle.draw_text(
			self,
			Vector2(0, baseline),
			text,
			UITokens.BONE,
			UITokens.FONT_BODY,
			size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)


## «НЕТ СИЛ» + «!» (AC-03.3): состояние продублировано знаком и текстом.
class _NoStaminaBadge extends Control:

	const TEXT: String = "НЕТ СИЛ"
	const SIZE := Vector2(80, 10)
	const BANG_SIZE: int = 7

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = SIZE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var rect := Rect2(Vector2.ZERO, size)
		draw_rect(rect, UITokens.BLOOD_9)
		UIStyle.draw_frame(self, rect, UITokens.BORDER_INNER, UITokens.BLOOD_3)
		UIStyle.draw_bang(
			self,
			Rect2(Vector2(1, 1), Vector2(BANG_SIZE, BANG_SIZE)),
			UITokens.BLOOD,
			UITokens.BONE
		)
		var baseline: float = (
			(size.y - UIStyle.text_height(UITokens.FONT_BODY)) * 0.5
			+ UIStyle.baseline_y(UITokens.FONT_BODY)
		)
		UIStyle.draw_text(
			self,
			Vector2(float(BANG_SIZE + 3), baseline),
			TEXT,
			UITokens.BONE,
			UITokens.FONT_BODY
		)


## Ступенчатая красная кайма по краю экрана при HP < 25 % (DESIGN §6.3).
## Рисуется только в 3/6/9 px от края — safe-зону контента не перекрывает.
class _CriticalEdge extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var alphas: Array[float] = [0.55, 0.32, 0.16]
		for index: int in alphas.size():
			var inset: float = float(index) * 3.0
			var rect := Rect2(
				Vector2(inset, inset),
				size - Vector2(inset * 2.0, inset * 2.0)
			)
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				return
			UIStyle.draw_frame(self, rect, 3, Color(UITokens.BLOOD, alphas[index]))


## Портрет — программная заглушка (арт T-05 заменит без изменения HUD).
class _PortraitFace extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0:
			return
		draw_rect(Rect2(Vector2.ZERO, size), UITokens.STEEL_9)
		var width: float = size.x
		# капюшон/шлем
		draw_rect(Rect2(2, 1, width - 4, 5), UITokens.STONE_3)
		# лицо
		draw_rect(Rect2(3, 6, width - 6, size.y - 9), UITokens.BONE)
		draw_rect(Rect2(3, 6, width - 6, 1), UITokens.STONE_9)
		# глаза
		draw_rect(Rect2(4, 8, 2, 2), UITokens.VOID)
		draw_rect(Rect2(width - 6, 8, 2, 2), UITokens.VOID)
		# наплечники
		draw_rect(Rect2(2, size.y - 3, width - 4, 2), UITokens.STEEL_9)


## Затемнённая полоса кулдауна снизу слота (AC-02.2, DESIGN §6.3).
class _CooldownStrip extends Control:

	var ratio: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var height: float = maxf(3.0, floor(size.y * 0.4))
		var width: float = floor(size.x * clampf(ratio, 0.0, 1.0))
		if width <= 0.0:
			return
		draw_rect(
			Rect2(0.0, size.y - height, width, height),
			Color(UITokens.VOID, 0.72)
		)
		draw_rect(Rect2(0.0, size.y - height, width, 1.0), UITokens.GOLD_9)


## Иконки кошелька (монета/свиток) — 8×8 из токенов.
class _WalletIcon extends Control:

	enum Kind { COIN, SCROLL }

	var kind: Kind = Kind.COIN

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(8, 8)

	func _draw() -> void:
		if kind == Kind.COIN:
			draw_rect(Rect2(1, 0, 6, 8), UITokens.GOLD_9)
			draw_rect(Rect2(0, 1, 8, 6), UITokens.GOLD_9)
			draw_rect(Rect2(2, 2, 4, 4), UITokens.GOLD_3)
		else:
			draw_rect(Rect2(1, 0, 6, 8), UITokens.BONE)
			draw_rect(Rect2(2, 2, 4, 1), UITokens.NIGHT_9)
			draw_rect(Rect2(2, 5, 4, 1), UITokens.NIGHT_9)


## Замок подсказки способности (та же форма, что у закрытого слота).
class _LockIcon extends Control:

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = UITokens.SLOT_LOCK_SIZE

	func _draw() -> void:
		UIStyle.draw_lock(self, Rect2(Vector2.ZERO, UITokens.SLOT_LOCK_SIZE), UITokens.STONE_5)
