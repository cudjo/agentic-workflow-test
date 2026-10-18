class_name Zone05Boss
extends BossBase
## Финальный босс «Пепельный Государь» (T-32).
##
## Три фазы нарастающей сложности (AC-03.4). Паттерны (id из
## `data/bosses/zone_05_boss.tres`):
##   * `ash_cleave` — ближний замах, только хитбокс;
##   * `pyre_fan`   — замах + веер снарядов (ближний бой не отменяется);
##   * `last_rites` — широкий веер, длинный рывок и призыв «эха».
##
## Сложность задаётся данными (урон/скорость/кулдаун/размер хитбокса), а не
## ветвлениями кода: подкласс лишь комбинирует доступные механики. Снаряды —
## `EnemyProjectile`, призывы — `Enemy` (переиспользуют боевое ядро T-10/T-12).
## Призванные враги убираются вместе с боссом; на арене держится лимит живых
## вызовов, чтобы финальный бой не «заливал» экран.

const MAX_ACTIVE_SUMMONS: int = 4
const MODE_MELEE: StringName = &"melee"
const MODE_HYBRID: StringName = &"hybrid"
const MODE_APOCALYPSE: StringName = &"apocalypse"

var _summoned: Array[Node] = []


func _perform_attack() -> void:
	var phase: BossPhaseData = data.get_phase(phase_index) if data != null else null
	if phase == null:
		return

	# Все три паттерна — гибридные: финальный босс не даёт «безопасной»
	# дистанции, с которой можно безнаказанно бить его из угла арены.
	match phase.pattern_id:
		&"ash_cleave":
			_activate_melee(phase)
		&"pyre_fan":
			_activate_melee(phase)
			_fire_projectile_fan(phase, maxi(phase.projectile_count, 1))
		&"last_rites":
			_activate_melee(phase)
			_fire_projectile_fan(phase, maxi(phase.projectile_count, 1))
			_summon_echoes(phase)
		_:
			push_warning(
				"Zone05Boss: unknown pattern '%s' in phase %d" % [
					phase.pattern_id,
					phase_index,
				]
			)
			_activate_melee(phase)


## Режим поведения фазы — для HUD/тестов: ближний, гибридный или апокалипсис.
func get_phase_mode() -> StringName:
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		return MODE_MELEE
	match phase.pattern_id:
		&"ash_cleave":
			return MODE_MELEE
		&"pyre_fan":
			return MODE_HYBRID
		&"last_rites":
			return MODE_APOCALYPSE
	return MODE_MELEE


func _finish_death() -> void:
	_clear_summons()
	super._finish_death()


## Веер снарядов вокруг направления на игрока. `count == 1` — одиночный
## выстрел; `projectile_spread_degrees` задаёт угол между соседними лучами.
func _fire_projectile_fan(phase: BossPhaseData, count: int) -> void:
	if count <= 0:
		return
	if data.projectile_scene == null:
		push_error("Zone05Boss: projectile_scene is missing for '%s'" % data.id)
		return
	var parent: Node = get_parent()
	if parent == null:
		return

	var base_direction: Vector2 = _direction_to_target()
	for index: int in count:
		var projectile := data.projectile_scene.instantiate() as EnemyProjectile
		if projectile == null:
			push_error("Zone05Boss: projectile scene is not an EnemyProjectile")
			return
		var centered_index: float = float(index) - float(count - 1) * 0.5
		var angle: float = deg_to_rad(phase.projectile_spread_degrees * centered_index)
		var direction: Vector2 = base_direction.rotated(angle)
		parent.add_child(projectile)
		projectile.global_position = (
			global_position
			+ Vector2(0.0, -data.body_size.y * 0.25)
			+ direction * (data.body_size.x * 0.5 + 4.0)
		)
		var payload: Damage = Damage.create(
			phase.attack_damage,
			Vector2.ZERO,
			balance.hit_flash_duration
		)
		projectile.setup(
			payload,
			phase.attack_knockback * balance.knockback_scale,
			direction,
			phase.projectile_speed,
			phase.projectile_lifetime
		)


func _summon_echoes(phase: BossPhaseData) -> void:
	if phase.summon_count <= 0:
		return
	if data.summon_scene == null:
		push_error("Zone05Boss: summon_scene is missing for '%s'" % data.id)
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
		var offset := Vector2(side * (40.0 + 12.0 * float(index / 2)), 0.0)
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


func _direction_to_target() -> Vector2:
	_validate_target()
	if target != null:
		var delta: Vector2 = target.global_position - global_position
		if not delta.is_zero_approx():
			return delta.normalized()
	return Vector2(float(facing), 0.0)
