class_name Corpse
extends Area2D
## Corpse — метка на месте гибели с инвентарём и валютой (T-26, AC-05.3).
##
## Спавнится DeathHandler'ом после возрождения игрока; позиция и содержимое
## живут в `GameState` (`corpse_*`), поэтому метка переживает загрузку сейва.
## Подбор — по контакту (`body_entered`, группа `player`): предметы и валюта
## возвращаются в инвентарь/кошелёк, метка исчезает.
##
## EC-05: если игрок умирает повторно до подбора, `GameState.drop_corpse()`
## очищает старую метку, а `mark_lost()` превращает этот узел в череп:
## `collect()` больше ничего не возвращает (потеря необратима).
##
## Иконка — мешок из `gold-9` (DESIGN §6.5); ассеты ещё не подключены, поэтому
## программная заглушка за тем же контрактом.

signal collected(items: Array, currency: int)

const PICKUP_LAYER: int = 0
## Слой 2 физики проекта — player (project.godot, [layer_names]).
const PLAYER_MASK: int = 1 << 1
const BAG_COLOR: Color = Color("#7d5a28")       # gold-9 (UITokens.GOLD_9)
const BAG_DARK: Color = Color("#4c3618")
const BAG_LIGHT: Color = Color("#c08a3e")       # gold
const BONE_COLOR: Color = Color("#d6c9a8")      # bone

var lost: bool = false
var _collected: bool = false


func _ready() -> void:
	add_to_group(&"corpses")
	collision_layer = PICKUP_LAYER
	collision_mask = PLAYER_MASK
	monitorable = false
	monitoring = not lost
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	queue_redraw()


## Настройка узла: позиция гибели и признак безвозвратной потери (EC-05).
func setup(at_position: Vector2, is_lost: bool = false) -> void:
	global_position = at_position
	lost = is_lost
	_collected = false
	visible = true
	_apply_state()
	queue_redraw()


## Метка потеряна навсегда: череп, подбор отключён (EC-05).
func mark_lost() -> void:
	lost = true
	_apply_state()
	queue_redraw()


## Подбор по контакту/вручную. Возвращает true, только если метка реально
## вернула содержимое игроку. Потерянная/пустая метка не подбирается.
func collect() -> bool:
	if lost or _collected:
		return false
	if not GameState.has_corpse() or GameState.is_corpse_lost():
		return false

	var loot: Dictionary = GameState.collect_corpse()
	if not bool(loot.get("collected", false)):
		return false

	_collected = true
	visible = false
	set_deferred(&"monitoring", false)
	set_deferred(&"monitorable", false)
	collected.emit(loot.get("items", []), int(loot.get("currency", 0)))
	return true


func is_collected() -> bool:
	return _collected


func _apply_state() -> void:
	# monitoring нельзя менять внутри physics-колбэка — отложенно.
	if is_inside_tree():
		set_deferred(&"monitoring", not lost and not _collected)
		set_deferred(&"monitorable", false)


func _on_body_entered(body: Node2D) -> void:
	if lost or _collected:
		return
	if not body.is_in_group(&"player"):
		return
	collect()


## Заглушка арта: мешок gold-9 (или череп у безвозвратной потери).
func _draw() -> void:
	if _collected:
		return
	if lost:
		# Череп: кость + тёмные глазницы (EC-05, DESIGN §6.5).
		draw_rect(Rect2(-4.0, -9.0, 8.0, 7.0), BONE_COLOR)
		draw_rect(Rect2(-3.0, -2.0, 6.0, 3.0), BONE_COLOR)
		draw_rect(Rect2(-3.0, -7.0, 2.0, 2.0), BAG_DARK)
		draw_rect(Rect2(1.0, -7.0, 2.0, 2.0), BAG_DARK)
		draw_rect(Rect2(-1.0, -3.0, 2.0, 1.0), BAG_DARK)
		return

	# Мешок: тёмное дно, золотая завязка, блик.
	draw_rect(Rect2(-6.0, -8.0, 12.0, 8.0), BAG_COLOR)
	draw_rect(Rect2(-6.0, -8.0, 12.0, 2.0), BAG_DARK)
	draw_rect(Rect2(-3.0, -11.0, 6.0, 3.0), BAG_COLOR)
	draw_rect(Rect2(-4.0, -10.0, 8.0, 1.0), BAG_LIGHT)
	draw_rect(Rect2(-5.0, -6.0, 2.0, 2.0), BAG_LIGHT)
