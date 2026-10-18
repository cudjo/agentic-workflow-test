class_name AbilityGate
extends Rubble
## AbilityGate — физический проход, требующий способность (T-09, PLAN §3.3).
##
## Поведение (AC-02.4, AC-04.3, EC-10):
##   * без способности `blocking = true`, коллизия включена, над препятствием
##     видна подсказка «Нужно: <СПОСОБНОСТЬ>» + замок (никакой скрытой
##     блокировки);
##   * `EventBus.ability_acquired(X)` открывает все живые gates с X сразу;
##   * уже пройденный альтернативным путём проход не блокируется: `mark_passed()`
##     фиксирует проход в статическом наборе по `gate_id`, поэтому повторно
##     созданный gate с тем же id открыт без способности (EC-10).
##
## Требование — данные, не хардкод: `gate_id` ищется в `data/ability_gates.tres`
## (`AbilityGateCatalog`); `ability_id` в инспекторе/метаданных `ability_gate`
## остаётся fallback для одиночных сцен и тестов. Подсказка — `AbilityHint`
## (локальный Label + замок), HUD T-19 получает
## `EventBus.ability_hint_changed` при входе/выходе игрока из зоны подсказки.
##
## Наследует `Rubble`: у завала та же физика (StaticBody2D, слой world),
## размер и сцена-заглушка арта; T-14/T-15-инстансы остаются совместимы.

signal opened

const CATALOG_PATH: String = "res://data/ability_gates.tres"
const HINT_MARGIN: float = 8.0
## Группа живых проходов: после загрузки сейва (schema v6) они переоценивают
## блокировку, не дожидаясь пересоздания сцены зоны.
const GROUP: StringName = &"ability_gates"

## id записи в `ability_gates.tres`; пусто — требование берётся из `ability_id`
## или метаданных `ability_gate` (совместимость с заглушками T-14/T-15).
@export var gate_id: StringName = &""
## Fallback-требование, если gate_id не описан данными.
@export var ability_id: StringName = &""
## Fallback-зона-доказательство пройденного маршрута (EC-10).
@export var proof_zone_id: StringName = &""
## Каталог требований; null — загружается `CATALOG_PATH`.
@export var catalog: AbilityGateCatalog

## Статический набор пройденных проходов: переживает пересоздание сцены зоны
## и восстанавливается из сейва (schema v6, `SaveSerializer.apply_session`).
static var _passed_gates: Dictionary = {}

@onready var hint: AbilityHint = get_node_or_null(^"AbilityHint") as AbilityHint
@onready var hint_area: Area2D = get_node_or_null(^"HintArea") as Area2D

var _resolved_ability: StringName = &""
var _hint_label: String = ""
var _resolved_proof_zone: StringName = &""
var _passed: bool = false
var _forced_open: bool = false
var _player_near: bool = false
var _hud_hint_active: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	super._ready()
	collision_layer = CombatLayers.WORLD
	collision_mask = 0
	_resolve_requirement()
	_passed = is_gate_passed(_gate_key())
	if not EventBus.ability_acquired.is_connected(_on_ability_acquired):
		EventBus.ability_acquired.connect(_on_ability_acquired)
	if (
		_resolved_proof_zone != &""
		and not SceneRouter.zone_visited.is_connected(_on_zone_visited)
	):
		SceneRouter.zone_visited.connect(_on_zone_visited)
	if hint_area != null:
		if not hint_area.body_entered.is_connected(_on_hint_body_entered):
			hint_area.body_entered.connect(_on_hint_body_entered)
		if not hint_area.body_exited.is_connected(_on_hint_body_exited):
			hint_area.body_exited.connect(_on_hint_body_exited)
	_refresh_state(false)


func _exit_tree() -> void:
	if _hud_hint_active and is_instance_valid(EventBus):
		_hud_hint_active = false
		EventBus.ability_hint_changed.emit(_resolved_ability, false)


# ------------------------------------------------------------------------------
# Контракт для сцен/тестов
# ------------------------------------------------------------------------------

func get_gate_id() -> StringName:
	return _gate_key()


func get_required_ability() -> StringName:
	return _resolved_ability


## Зона, посещение которой уже доказывает проход (EC-10); `&""` — нет.
func get_proof_zone_id() -> StringName:
	return _resolved_proof_zone


func is_open() -> bool:
	return not blocking


func is_passed() -> bool:
	return _passed


func get_hint() -> AbilityHint:
	return hint


func get_hint_text() -> String:
	return hint.get_text() if hint != null else ""


## Помечает проход уже пройденным (альтернативный маршрут, EC-10).
## Проход остаётся открытым без способности, в том числе после пересоздания
## сцены в этой сессии.
func mark_passed() -> void:
	if _passed:
		return
	_passed = true
	mark_gate_passed(_gate_key())
	_refresh_state(true)


## Открыть принудительно (скрипты/отладка); требование при этом считается
## выполненным только для этого узла — набор способностей не меняется.
func open() -> void:
	if not blocking:
		return
	_forced_open = true
	blocking = false
	if hint != null:
		hint.hide_hint()
	_update_hud_hint()
	opened.emit()


# ------------------------------------------------------------------------------
# Статический учёт пройденных проходов (EC-10)
# ------------------------------------------------------------------------------

static func mark_gate_passed(passed_gate_id: StringName) -> void:
	if passed_gate_id != &"":
		_passed_gates[passed_gate_id] = true


static func is_gate_passed(passed_gate_id: StringName) -> bool:
	return passed_gate_id != &"" and _passed_gates.has(passed_gate_id)


## Копия набора пройденных проходов для сейва (schema v6). Порядок — порядок
## первого прохода, мутация результата не меняет набор.
static func get_passed_gate_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _passed_gates.keys():
		ids.append(StringName(str(key)))
	return ids


## Восстанавливает набор пройденных проходов из сейва (schema v6, EC-10).
## Идемпотентно: набор заменяется, живые gates переоценивают блокировку —
## уже пройденный маршрут не блокирует игрока после загрузки.
static func restore_passed_gates(gate_ids: Array) -> void:
	_passed_gates.clear()
	for value: Variant in gate_ids:
		mark_gate_passed(StringName(str(value)))
	refresh_live_gates()


## Переоценивает живые проходы по актуальному набору (загрузка сейва при уже
## созданной зоне). Пройденность берётся только из набора: загруженный сейв —
## источник истины, а не состояние узлов прошлой сессии.
static func refresh_live_gates() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(GROUP):
		var gate: AbilityGate = node as AbilityGate
		if gate == null or not is_instance_valid(gate):
			continue
		gate._passed = is_gate_passed(gate._gate_key())
		gate._refresh_state(true)


## Сброс для новой игры/тестов.
static func reset_passed_gates() -> void:
	_passed_gates.clear()


# ------------------------------------------------------------------------------
# Внутреннее
# ------------------------------------------------------------------------------

func _gate_key() -> StringName:
	if gate_id != &"":
		return gate_id
	# Узлы в одной зоне уникальны по имени; сцены с данными задают gate_id.
	return StringName(name)


func _resolve_requirement() -> void:
	var data: AbilityGateData = _gate_data()
	if data != null:
		_resolved_ability = data.ability_id
		_hint_label = data.hint_label
		_resolved_proof_zone = data.proof_zone_id
	if _resolved_ability == &"":
		_resolved_ability = ability_id
	if _resolved_proof_zone == &"":
		_resolved_proof_zone = proof_zone_id
	if _resolved_ability == &"" and has_meta(&"ability_gate"):
		_resolved_ability = StringName(str(get_meta(&"ability_gate")))
	if _resolved_ability == &"":
		push_error(
			"AbilityGate '%s': no ability requirement (gate_id='%s')" % [name, gate_id]
		)
	elif not AbilityRegistry.has_ability(_resolved_ability):
		push_warning(
			"AbilityGate '%s': unknown ability '%s'" % [name, _resolved_ability]
		)


func _gate_data() -> AbilityGateData:
	var resolved_catalog: AbilityGateCatalog = _load_catalog()
	if resolved_catalog == null or gate_id == &"":
		return null
	return resolved_catalog.get_gate(gate_id)


func _load_catalog() -> AbilityGateCatalog:
	if catalog == null and ResourceLoader.exists(CATALOG_PATH):
		catalog = load(CATALOG_PATH) as AbilityGateCatalog
	return catalog


func _refresh_state(emit_opened: bool) -> void:
	var unlocks: bool = _passed or _forced_open or _route_already_passed()
	if not unlocks and _resolved_ability != &"":
		unlocks = GameState.has_ability(_resolved_ability)
	var was_blocking: bool = blocking
	blocking = not unlocks

	if hint != null:
		if blocking:
			hint.show_required(_resolved_ability, _hint_label)
		else:
			hint.hide_hint()
		_sync_hint_position()

	_update_hud_hint()

	if emit_opened and was_blocking and not blocking:
		opened.emit()


func _update_hud_hint() -> void:
	var required: bool = (
		blocking
		and _player_near
		and _resolved_ability != &""
		and not GameState.has_ability(_resolved_ability)
	)
	if required == _hud_hint_active:
		return
	_hud_hint_active = required
	EventBus.ability_hint_changed.emit(_resolved_ability, required)


func _sync_hint_position() -> void:
	if hint == null:
		return
	var half_height: float = 12.0
	var top: float = -24.0
	if collision_shape != null and collision_shape.shape is RectangleShape2D:
		var rect: RectangleShape2D = collision_shape.shape as RectangleShape2D
		half_height = rect.size.y * 0.5
		top = collision_shape.position.y - half_height
	var scale_y: float = absf(global_scale.y)
	hint.set_world_position(global_position + Vector2(0.0, top * scale_y - HINT_MARGIN))


func _on_ability_acquired(acquired: StringName) -> void:
	if acquired != _resolved_ability:
		return
	_refresh_state(true)


## EC-10: другой маршрут уже привёл в зону за препятствием — не блокируем.
func _route_already_passed() -> bool:
	return _resolved_proof_zone != &"" and SceneRouter.is_zone_visited(_resolved_proof_zone)


func _on_zone_visited(zone_id: StringName) -> void:
	if zone_id == _resolved_proof_zone:
		_refresh_state(true)


func _on_hint_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_near = true
	_update_hud_hint()


func _on_hint_body_exited(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	_player_near = false
	_update_hud_hint()


## Заглушка арта: каменная плита с золотым замком; открытый проход — порог.
func _draw() -> void:
	if blocking:
		draw_rect(Rect2(-16.0, -24.0, 32.0, 24.0), UITokens.BROWN_9)
		draw_rect(Rect2(-15.0, -23.0, 30.0, 22.0), UITokens.BROWN)
		draw_rect(Rect2(-15.0, -23.0, 30.0, 1.0), UITokens.BROWN_3)
		draw_rect(Rect2(-12.0, -19.0, 24.0, 1.0), UITokens.STONE_9)
		# Замок в центре плиты.
		draw_rect(Rect2(-5.0, -13.0, 10.0, 8.0), UITokens.GOLD_9)
		draw_rect(Rect2(-4.0, -12.0, 8.0, 6.0), UITokens.GOLD_3)
		draw_rect(Rect2(-1.0, -15.0, 2.0, 2.0), UITokens.GOLD_3)
		draw_rect(Rect2(-1.0, -9.0, 2.0, 2.0), UITokens.VOID)
	else:
		draw_rect(Rect2(-16.0, -2.0, 32.0, 2.0), UITokens.STONE_9)
		draw_rect(Rect2(-16.0, -2.0, 2.0, 2.0), UITokens.STONE_3)
		draw_rect(Rect2(14.0, -2.0, 2.0, 2.0), UITokens.STONE_3)
