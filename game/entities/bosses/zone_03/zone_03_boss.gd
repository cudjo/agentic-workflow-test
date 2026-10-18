class_name Zone03Boss
extends BossBase
## Босс зоны 3 «Ледяной Обвал» (T-31) — горный перевал.
##
## Паттерны (id из `data/bosses/zone_03_boss.tres`):
##   * `glacier_cleave` — ближний замах с длинным холодным телеграфом;
##   * `rockslide`      — замах + камнепад в вертикальных шахтах арены;
##   * `avalanche`      — замах + обвал по всем колоннам шахт и рывок.
##
## Механика зоны: перевал — это вертикальные шахты. Босс не просто бьёт
## вблизи, а «роняет» камни по фиксированным колоннам (`shaft_offsets`),
## поэтому игрок читает предупреждение и уходит из-под удара, используя
## горизонтальную подвижность/рывок. Урон идёт через `BossHazard` (боевое
## ядро T-10), тайминги — из `BossPhaseData.hazard_*`.
##
## Сложность фаз задаётся данными: ширина обвала (hazard_count), telegraph,
## скорость падения и урон растут, а окно реакции сокращается.

const MODE_GLACIER: StringName = &"glacier"
const MODE_ROCKSLIDE: StringName = &"rockslide"
const MODE_AVALANCHE: StringName = &"avalanche"

## Колонны вертикальных шахт относительно центра арены (px).
@export var shaft_offsets: PackedFloat32Array = PackedFloat32Array([
	-144.0, -72.0, 0.0, 72.0, 144.0,
])
@export var rock_size: Vector2 = Vector2(14.0, 14.0)
@export var rock_fall_speed: float = 260.0
@export var rock_color: Color = Color(0.62, 0.72, 0.79, 1.0)
@export var warning_color: Color = UITokens.STEEL_3

var _hazards: Array[BossHazard] = []


func _perform_attack() -> void:
	var phase: BossPhaseData = data.get_phase(phase_index) if data != null else null
	if phase == null:
		return
	match phase.pattern_id:
		&"glacier_cleave":
			_activate_melee(phase)
		&"rockslide", &"avalanche":
			_activate_melee(phase)
			_spawn_rockfall(phase)
		_:
			push_warning(
				"Zone03Boss: unknown pattern '%s' in phase %d" % [
					phase.pattern_id,
					phase_index,
				]
			)
			_activate_melee(phase)


## Режим фазы для HUD/тестов: ближний, камнепад или обвал.
func get_phase_mode() -> StringName:
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		return MODE_GLACIER
	match phase.pattern_id:
		&"glacier_cleave":
			return MODE_GLACIER
		&"rockslide":
			return MODE_ROCKSLIDE
		&"avalanche":
			return MODE_AVALANCHE
	return MODE_GLACIER


## Мировые X-колонны шахт для `count` камней (тесты/арена/отладка).
func get_hazard_columns(count: int) -> Array[float]:
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


func _spawn_rockfall(phase: BossPhaseData) -> void:
	if phase.hazard_count <= 0:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var floor_y: float = _arena_floor_y()
	var start_y: float = _arena_ceiling_y()
	for column_x: float in get_hazard_columns(phase.hazard_count):
		var hazard := BossHazard.new()
		hazard.name = "FallingRock"
		var payload: Damage = Damage.create(
			phase.hazard_damage,
			Vector2.ZERO,
			balance.hit_flash_duration
		)
		hazard.configure(
			BossHazard.Kind.FALLING_ROCK,
			payload,
			phase.hazard_knockback * balance.knockback_scale,
			phase.hazard_telegraph,
			phase.hazard_active,
			Vector2.DOWN,
			rock_fall_speed,
			rock_size,
			rock_color,
			warning_color
		)
		parent.add_child(hazard)
		hazard.place_at(Vector2(column_x, start_y), floor_y)
		hazard.resolved.connect(_on_hazard_resolved)
		_hazards.append(hazard)


func _on_hazard_resolved(hazard: BossHazard) -> void:
	_hazards.erase(hazard)


func _pick_offsets(count: int) -> Array[float]:
	var offsets: Array[float] = []
	if shaft_offsets.is_empty() or count <= 0:
		return offsets
	var available: int = shaft_offsets.size()
	if count >= available:
		for value: float in shaft_offsets:
			offsets.append(value)
		return offsets
	if count == 1:
		offsets.append(0.0)
		return offsets
	var step: float = float(available - 1) / float(count - 1)
	for index: int in count:
		var offset_index: int = clampi(roundi(step * float(index)), 0, available - 1)
		offsets.append(shaft_offsets[offset_index])
	return offsets


func _arena_floor_y() -> float:
	if arena_bounds.size.y > 0.0:
		return arena_bounds.end.y
	var body_height: float = data.body_size.y if data != null else 40.0
	return global_position.y + body_height * 0.5 + 8.0


func _arena_ceiling_y() -> float:
	if arena_bounds.size.y > 0.0:
		return arena_bounds.position.y + 8.0
	var body_height: float = data.body_size.y if data != null else 40.0
	return global_position.y - body_height * 4.0


func _arena_center_x() -> float:
	if arena_bounds.size.x > 0.0:
		return arena_bounds.get_center().x
	return global_position.x


# ------------------------------------------------------------------------------
# Telegraph: холодный иней на теле перед ударом (уникален для зоны 3)
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
	var blink: float = 0.5 + 0.5 * float(int(attack_timer * 20.0) % 2)
	visual.modulate = data.get_body_color().lerp(
		warning_color,
		(0.25 + 0.4 * progress) * blink
	)
	visual.scale = Vector2(1.0 + 0.2 * progress, 1.0 + 0.1 * progress)


func _reset_telegraph() -> void:
	if visual == null or data == null or is_dead:
		return
	# Масштаб сбрасываем всегда: вспышка попадания меняет только цвет, и
	# иначе увеличенный силуэт мог бы остаться до следующего замаха.
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
	# Сбрасываем telegraph до is_dead: иначе силуэт застынет увеличенным.
	_reset_telegraph()
	super._die()


func _finish_death() -> void:
	_clear_hazards()
	super._finish_death()
