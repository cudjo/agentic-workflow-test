class_name Zone04Boss
extends BossBase
## Босс зоны 4 «Хранитель Печати» (T-31) — руины-храм.
##
## Паттерны (id из `data/bosses/zone_04_boss.tres`):
##   * `seal_cleave` — ближний замах с тяжёлым телеграфом;
##   * `trap_ritual` — замах + руны-ловушки на полу (механика рычагов/ловушек);
##   * `seal_break`  — замах + ловушки по всей арене и призыв «эха стражи».
##
## Механика зоны: руины — это зал с рычагами и скрытыми плитами. Босс
## «читает» печать: на полу по фиксированным позициям (`trap_offsets`)
## вспыхивают руны, затем из них выходят шипы. У игрока есть telegraph
## (`hazard_telegraph`), чтобы перепрыгнуть/сместиться. Урон — `BossHazard`
## (боевое ядро T-10), призывы — обычные `Enemy` (T-12).

const MODE_SEAL: StringName = &"seal"
const MODE_TRAPS: StringName = &"traps"
const MODE_BREAK: StringName = &"seal_break"
const MAX_ACTIVE_SUMMONS: int = 4

## Позиции рун-ловушек относительно центра арены (px).
@export var trap_offsets: PackedFloat32Array = PackedFloat32Array([
	-156.0, -104.0, -52.0, 0.0, 52.0, 104.0, 156.0,
])
@export var trap_size: Vector2 = Vector2(26.0, 14.0)
@export var trap_color: Color = Color(0.75, 0.54, 0.24, 1.0)
@export var warning_color: Color = UITokens.BLOOD_3

var _hazards: Array[BossHazard] = []
var _summoned: Array[Node] = []


func _perform_attack() -> void:
	var phase: BossPhaseData = data.get_phase(phase_index) if data != null else null
	if phase == null:
		return
	match phase.pattern_id:
		&"seal_cleave":
			_activate_melee(phase)
		&"trap_ritual":
			_activate_melee(phase)
			_spawn_traps(phase)
		&"seal_break":
			_activate_melee(phase)
			_spawn_traps(phase)
			_summon_wardens(phase)
		_:
			push_warning(
				"Zone04Boss: unknown pattern '%s' in phase %d" % [
					phase.pattern_id,
					phase_index,
				]
			)
			_activate_melee(phase)


## Режим фазы для HUD/тестов: печать, ловушки или разрыв печати.
func get_phase_mode() -> StringName:
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		return MODE_SEAL
	match phase.pattern_id:
		&"seal_cleave":
			return MODE_SEAL
		&"trap_ritual":
			return MODE_TRAPS
		&"seal_break":
			return MODE_BREAK
	return MODE_SEAL


## Мировые X-позиции рун-ловушек (тесты/арена/отладка).
func get_trap_columns(count: int) -> Array[float]:
	var columns: Array[float] = []
	if count <= 0:
		return columns
	var center_x: float = _arena_center_x()
	for offset: float in _pick_offsets(count):
		columns.append(center_x + offset)
	return columns


func get_active_hazards() -> Array[BossHazard]:
	var alive: Array[BossHazard] = []
	for hazard: BossHazard in _hazards:
		if is_instance_valid(hazard):
			alive.append(hazard)
	_hazards = alive
	return _hazards.duplicate()


func _spawn_traps(phase: BossPhaseData) -> void:
	if phase.hazard_count <= 0:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var floor_y: float = _arena_floor_y()
	for column_x: float in get_trap_columns(phase.hazard_count):
		var hazard := BossHazard.new()
		hazard.name = "RuneTrap"
		var payload: Damage = Damage.create(
			phase.hazard_damage,
			Vector2.ZERO,
			balance.hit_flash_duration
		)
		hazard.configure(
			BossHazard.Kind.SPIKE_TRAP,
			payload,
			phase.hazard_knockback * balance.knockback_scale,
			phase.hazard_telegraph,
			phase.hazard_active,
			Vector2.UP,
			0.0,
			trap_size,
			trap_color,
			warning_color
		)
		parent.add_child(hazard)
		hazard.place_at(Vector2(column_x, floor_y), floor_y)
		hazard.resolved.connect(_on_hazard_resolved)
		_hazards.append(hazard)


func _on_hazard_resolved(hazard: BossHazard) -> void:
	_hazards.erase(hazard)


func _pick_offsets(count: int) -> Array[float]:
	var offsets: Array[float] = []
	if trap_offsets.is_empty() or count <= 0:
		return offsets
	var available: int = trap_offsets.size()
	if count >= available:
		for value: float in trap_offsets:
			offsets.append(value)
		return offsets
	if count == 1:
		offsets.append(0.0)
		return offsets
	var step: float = float(available - 1) / float(count - 1)
	for index: int in count:
		var offset_index: int = clampi(roundi(step * float(index)), 0, available - 1)
		offsets.append(trap_offsets[offset_index])
	return offsets


func _arena_floor_y() -> float:
	if arena_bounds.size.y > 0.0:
		return arena_bounds.end.y
	var body_height: float = data.body_size.y if data != null else 42.0
	return global_position.y + body_height * 0.5 + 8.0


func _arena_center_x() -> float:
	if arena_bounds.size.x > 0.0:
		return arena_bounds.get_center().x
	return global_position.x


# ------------------------------------------------------------------------------
# Summons: «эхо стражи» (T-12), лимит живых — чтобы не заливать арену
# ------------------------------------------------------------------------------

func _summon_wardens(phase: BossPhaseData) -> void:
	if phase.summon_count <= 0:
		return
	if data.summon_scene == null:
		push_error("Zone04Boss: summon_scene is missing for '%s'" % data.id)
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var active: int = _count_active_summons()
	var spawn_count: int = mini(phase.summon_count, MAX_ACTIVE_SUMMONS - active)
	for index: int in spawn_count:
		var minion := data.summon_scene.instantiate()
		if minion == null:
			continue
		parent.add_child(minion)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var offset := Vector2(side * (48.0 + 12.0 * float(index / 2)), 0.0)
		if minion is Node2D:
			(minion as Node2D).global_position = global_position + offset
		if minion is Enemy:
			var enemy := minion as Enemy
			enemy.set_home_position(enemy.global_position)
		_summoned.append(minion)


func _count_active_summons() -> int:
	var alive: Array[Node] = []
	for minion: Node in _summoned:
		if not is_instance_valid(minion):
			continue
		if minion is Enemy and (minion as Enemy).is_dead:
			continue
		alive.append(minion)
	_summoned = alive
	return _summoned.size()


func _clear_summons() -> void:
	for minion: Node in _summoned:
		if is_instance_valid(minion):
			minion.queue_free()
	_summoned.clear()


# ------------------------------------------------------------------------------
# Telegraph: тёплая печать + дрожь тела перед ударом (уникален для зоны 4)
# ------------------------------------------------------------------------------

func _tick_attack(delta: float) -> void:
	super._tick_attack(delta)
	_tick_telegraph()


func _on_state_changed(
	from_state: EnemyStateMachine.State,
	to_state: EnemyStateMachine.State
) -> void:
	super._on_state_changed(from_state, to_state)
	if to_state != EnemyStateMachine.State.ATTACK:
		_reset_telegraph()


func _tick_telegraph() -> void:
	var phase: BossPhaseData = _current_phase()
	if visual == null or data == null or phase == null or fsm == null:
		return
	if _flash_time_left > 0.0:
		return
	var in_windup: bool = (
		fsm.current == EnemyStateMachine.State.ATTACK
		and not _attack_performed
		and attack_timer < phase.windup
	)
	if not in_windup:
		_reset_telegraph()
		return
	var progress: float = clampf(attack_timer / maxf(phase.windup, 0.001), 0.0, 1.0)
	var shake: float = 1.0 if int(attack_timer * 30.0) % 2 == 0 else -1.0
	visual.position.x = shake * (1.0 + 2.0 * progress)
	visual.modulate = data.get_body_color().lerp(warning_color, 0.3 + 0.5 * progress)


func _reset_telegraph() -> void:
	if visual == null or data == null or is_dead:
		return
	visual.position.x = 0.0
	visual.scale = Vector2.ONE
	if _flash_time_left <= 0.0:
		visual.modulate = data.get_body_color()


func _clear_hazards() -> void:
	for hazard: BossHazard in _hazards:
		if is_instance_valid(hazard):
			hazard.queue_free()
	_hazards.clear()


func _die() -> void:
	_clear_hazards()
	_clear_summons()
	# Сбрасываем telegraph до is_dead: иначе дрожь силуэта останется на смерти.
	_reset_telegraph()
	super._die()


func _finish_death() -> void:
	_clear_hazards()
	_clear_summons()
	super._finish_death()
