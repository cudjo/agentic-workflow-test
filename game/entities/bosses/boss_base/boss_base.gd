class_name BossBase
extends CharacterBody2D
## BossBase — база босса (T-30): CharacterBody2D с 2–3 фазами, сменой
## паттерна по порогу HP и уведомлением HUD (AC-03.4).
##
## Переиспользует боевое ядро T-10 (`Hitbox`/`Hurtbox`/`Damage`/`CombatLayers`)
## и поведенческий FSM T-12 (`EnemyStateMachine`: CHASE/ATTACK/HURT/DEATH).
## Наследование от `Enemy` намеренно не используется: враг привязан к
## `EnemyData` (патруль, leash, spawner) и не знает о фазах/арене/награде.
## Общими остаются контракты урона, вспышки, отбрасывания и слоёв.
##
## Данные — `data/bosses/*.tres` (`BossData` + `BossPhaseData`), общие
## тайминги (вспышка, отшатывание, длительность смерти/перехода фазы) —
## `balancing.tres`. Флаг «босс мёртв» и награда живут в `GameState`
## (персистентно через SaveManager), поэтому босс остаётся мёртвым (EC-09).
##
## Контракт паттернов: база ведёт тайминги windup/active/recovery и движение,
## подкласс реализует `_perform_attack()` по `phase.pattern_id`.

## Фаза изменилась; индекс — новый. Потребители: арена/тесты/будущий звук.
signal phase_changed(boss: BossBase, phase_index: int)
## Босс побеждён (награда уже поставлена в очередь GameState).
signal defeated(boss: BossBase)

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const PLAYER_GROUP: StringName = &"player"
const BOSS_GROUP: StringName = &"bosses"

@export var data: BossData
@export var balance: BalancingParams
## Стартовать бой сразу (арены/тесты); в игре бой открывает BossArena.
@export var auto_start: bool = false
## Мировые границы арены; Rect2() с нулевым размером — без ограничения.
@export var arena_bounds: Rect2 = Rect2()

var hp: float = 0.0
var phase_index: int = 0
var facing: int = -1
var target: Node2D = null
var fsm: EnemyStateMachine
var is_dead: bool = false
var fight_active: bool = false
var attack_timer: float = 0.0
var attack_cooldown_left: float = 0.0

var _attack_performed: bool = false
var _attack_hitbox_live: bool = false
var _death_elapsed: float = 0.0
var _phase_invulnerable_left: float = 0.0
var _flash_time_left: float = 0.0

@onready var visual: Sprite2D = $Visual
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = $Hitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurt_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var attack_shape: CollisionShape2D = $Hitbox/CollisionShape2D


func _ready() -> void:
	add_to_group(BOSS_GROUP)
	if data == null:
		push_error("BossBase: data resource is missing on %s" % name)
		set_physics_process(false)
		return
	if not data.is_valid():
		push_error("BossBase: invalid BossData '%s'" % data.id)
	if balance == null:
		balance = GameState.balance if GameState != null else null
	if balance == null:
		balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("BossBase: balancing resource is missing at %s" % BALANCE_PATH)
		set_physics_process(false)
		return

	hp = data.max_hp
	phase_index = 0
	facing = -1
	_apply_data()
	_configure_combat()
	fsm = EnemyStateMachine.new()
	fsm.state_changed.connect(_on_state_changed)
	_set_facing(facing)
	if auto_start:
		activate_fight.call_deferred()


func _physics_process(delta: float) -> void:
	if data == null or balance == null or fsm == null:
		return
	if is_dead:
		_tick_death(delta)
		return

	fsm.tick(delta)
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	_tick_phase_invulnerability(delta)

	if not fight_active:
		_apply_gravity(delta)
		return

	match fsm.current:
		EnemyStateMachine.State.CHASE:
			_tick_chase(delta)
		EnemyStateMachine.State.ATTACK:
			_tick_attack(delta)
		EnemyStateMachine.State.HURT:
			_tick_hurt(delta)
		EnemyStateMachine.State.DEATH:
			_tick_death(delta)
			return

	_tick_hit_flash(delta)
	_apply_gravity(delta)
	_clamp_to_arena()


# ------------------------------------------------------------------------------
# Fight lifecycle (arena calls this)
# ------------------------------------------------------------------------------

## Начинает бой. Возвращает false, если босс уже мёртв/побеждён ранее (EC-09).
func activate_fight() -> bool:
	if data == null or is_dead:
		return false
	if GameState != null and GameState.is_boss_defeated(data.id):
		_remove_defeated_instance()
		return false
	if fight_active:
		return true
	fight_active = true
	target = _find_target()
	fsm.force_state(EnemyStateMachine.State.CHASE)
	_enter_phase(phase_index, false)
	EventBus.boss_fight_started.emit(
		data.id,
		data.display_name,
		data.max_hp,
		data.get_phase_thresholds()
	)
	return true


## Побеждённый ранее босс не появляется в зоне (EC-09).
func _remove_defeated_instance() -> void:
	is_dead = true
	fight_active = false
	visible = false
	hurtbox.set_invulnerable(true)
	hurtbox.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	queue_free()


# ------------------------------------------------------------------------------
# FSM state ticks
# ------------------------------------------------------------------------------

func _tick_chase(delta: float) -> void:
	_validate_target()
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		velocity.x = 0.0
		return

	if target == null:
		velocity.x = move_toward(velocity.x, 0.0, phase.move_speed * 2.0 * delta)
		return

	_face_target()
	var distance: float = absf(target.global_position.x - global_position.x)
	if distance <= phase.attack_range and attack_cooldown_left <= 0.0:
		if fsm.request_state(EnemyStateMachine.State.ATTACK):
			return

	var direction: int = 0
	if phase.preferred_distance > 0.0 and distance < phase.preferred_distance:
		direction = -1 if target.global_position.x > global_position.x else 1
	elif distance > phase.attack_range:
		direction = 1 if target.global_position.x > global_position.x else -1
	velocity.x = float(direction) * phase.move_speed


func _tick_attack(delta: float) -> void:
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		fsm.force_state(EnemyStateMachine.State.CHASE)
		return

	attack_timer += delta
	var active_start: float = maxf(phase.windup, 0.0)
	var active_end: float = active_start + maxf(phase.active, 0.0)

	if not _attack_performed and attack_timer >= active_start:
		_perform_attack()
		_attack_performed = true

	var lunging: bool = (
		phase.lunge_speed > 0.0
		and attack_timer >= active_start
		and attack_timer < active_end
	)
	velocity.x = float(facing) * phase.lunge_speed if lunging else 0.0

	if _attack_hitbox_live and attack_timer >= active_end:
		attack_hitbox.deactivate()
		_attack_hitbox_live = false

	if attack_timer >= phase.get_attack_total_time():
		attack_hitbox.deactivate()
		_attack_hitbox_live = false
		attack_cooldown_left = phase.attack_cooldown
		fsm.force_state(EnemyStateMachine.State.CHASE)


func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(
		velocity.x,
		0.0,
		maxf(balance.enemy_knockback_friction, 0.0) * delta
	)
	if fsm.time_in_state < balance.t_hurt:
		return
	fsm.force_state(EnemyStateMachine.State.CHASE)


func _tick_death(delta: float) -> void:
	_death_elapsed += delta
	var fade_duration: float = maxf(balance.boss_death_duration, 0.001)
	var progress: float = clampf(_death_elapsed / fade_duration, 0.0, 1.0)
	if visual != null:
		var color: Color = data.get_body_color()
		color.a = 1.0 - progress
		visual.modulate = color
		visual.scale = Vector2(1.0 + 0.1 * progress, 1.0 - 0.3 * progress)
	if _death_elapsed >= fade_duration:
		_finish_death()


# ------------------------------------------------------------------------------
# Attack hooks (subclasses)
# ------------------------------------------------------------------------------

## Реализация паттерна текущей фазы. База — ближний хитбокс.
func _perform_attack() -> void:
	var phase: BossPhaseData = _current_phase()
	if phase == null:
		return
	_activate_melee(phase)


## Включает ближний хитбокс с параметрами фазы (melee-боссы).
func _activate_melee(phase: BossPhaseData) -> void:
	attack_hitbox.position = Vector2(
		phase.attack_offset.x * float(facing),
		phase.attack_offset.y
	)
	var payload: Damage = Damage.create(
		phase.attack_damage,
		Vector2.ZERO,
		balance.hit_flash_duration
	)
	var knockback_force: float = phase.attack_knockback * balance.knockback_scale
	attack_hitbox.clear_hits()
	attack_hitbox.activate(payload, knockback_force, Vector2(float(facing), 0.0))
	_attack_hitbox_live = true


# ------------------------------------------------------------------------------
# Damage / phases / death
# ------------------------------------------------------------------------------

func _on_hurtbox_damaged(damage: Damage) -> void:
	if is_dead or not fight_active or damage == null or fsm == null:
		return
	if _phase_invulnerable_left > 0.0:
		return

	hp = maxf(hp - damage.amount, 0.0)
	_start_hit_flash(damage)
	_apply_incoming_knockback(damage)
	EventBus.boss_health_changed.emit(data.id, hp, data.max_hp)

	if hp <= 0.0:
		_die()
		return

	var new_phase: int = data.get_phase_index_for_ratio(get_health_ratio())
	if new_phase > phase_index:
		_enter_phase(new_phase, true)
		return

	if damage.amount >= data.poise:
		_stop_attack_hitbox()
		if fsm.current == EnemyStateMachine.State.HURT:
			fsm.time_in_state = 0.0
		else:
			fsm.request_state(EnemyStateMachine.State.HURT)


## Переход на фазу: смена паттерна, уведомление HUD и короткая неуязвимость.
func _enter_phase(new_index: int, notify: bool) -> void:
	var phase: BossPhaseData = data.get_phase(new_index)
	if phase == null:
		return
	phase_index = new_index
	attack_timer = 0.0
	_attack_performed = false
	attack_cooldown_left = 0.0
	_stop_attack_hitbox()
	_apply_attack_shape(phase)
	if fsm != null and fsm.current != EnemyStateMachine.State.DEATH:
		fsm.force_state(EnemyStateMachine.State.CHASE)
	if balance != null and notify and balance.boss_phase_transition_time > 0.0:
		_phase_invulnerable_left = balance.boss_phase_transition_time
		hurtbox.set_invulnerable(true)
	if notify:
		phase_changed.emit(self, phase_index)
		EventBus.boss_health_changed.emit(data.id, hp, data.max_hp)
		EventBus.boss_phase_changed.emit(data.id, phase_index, phase.title)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	fight_active = false
	fsm.force_state(EnemyStateMachine.State.DEATH)
	_death_elapsed = 0.0
	_stop_attack_hitbox()
	hurtbox.set_invulnerable(true)
	hurtbox.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	velocity = Vector2.ZERO


func _finish_death() -> void:
	if data == null or data.reward == null:
		queue_free()
		return

	GameState.mark_boss_defeated(data.id)
	GameState.queue_boss_reward(
		data.id,
		data.zone_id,
		data.reward.id,
		data.reward.gold
	)
	EventBus.boss_defeated.emit(data.id, data.zone_id, global_position)
	defeated.emit(self)

	# Награда сразу, если игрок жив; иначе — при следующем входе в зону (EC-09).
	if _is_player_alive():
		GameState.claim_boss_reward(data.id)
	queue_free()


func _is_player_alive() -> bool:
	_validate_target()
	if target == null:
		return true
	var dead_value: Variant = target.get("is_dead")
	return not (dead_value is bool and dead_value)


# ------------------------------------------------------------------------------
# Public queries (HUD, tests, arena)
# ------------------------------------------------------------------------------

func get_health_ratio() -> float:
	if data == null or data.max_hp <= 0.0:
		return 0.0
	return clampf(hp / data.max_hp, 0.0, 1.0)


func get_phase_title() -> String:
	var phase: BossPhaseData = _current_phase()
	return phase.title if phase != null else ""


func get_pattern_id() -> StringName:
	var phase: BossPhaseData = _current_phase()
	return phase.pattern_id if phase != null else &""


func get_phase_count() -> int:
	return data.get_phase_count() if data != null else 0


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _current_phase() -> BossPhaseData:
	return data.get_phase(phase_index) if data != null else null


func _validate_target() -> void:
	if target != null and is_instance_valid(target):
		return
	target = _find_target()


func _find_target() -> Node2D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(PLAYER_GROUP) as Node2D


func _face_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	_set_facing(1 if target.global_position.x >= global_position.x else -1)


func _set_facing(direction: int) -> void:
	if direction == 0:
		return
	facing = -1 if direction < 0 else 1
	if visual != null:
		visual.flip_h = facing < 0
	var phase: BossPhaseData = _current_phase()
	if attack_hitbox != null and phase != null:
		attack_hitbox.position = Vector2(
			phase.attack_offset.x * float(facing),
			phase.attack_offset.y
		)


func _apply_gravity(delta: float) -> void:
	velocity.y += balance.get_gravity() * delta
	move_and_slide()
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0


## Босс не выходит за арену даже рывком (арена ставит мировые границы).
func _clamp_to_arena() -> void:
	if arena_bounds.size.x <= 0.0 or arena_bounds.size.y <= 0.0:
		return
	var half: Vector2 = data.body_size * 0.5
	var min_x: float = arena_bounds.position.x + half.x
	var max_x: float = arena_bounds.end.x - half.x
	var previous_x: float = global_position.x
	global_position.x = clampf(global_position.x, min_x, max_x)
	if not is_equal_approx(previous_x, global_position.x):
		velocity.x = 0.0


func _on_state_changed(
	from_state: EnemyStateMachine.State,
	to_state: EnemyStateMachine.State
) -> void:
	if from_state == EnemyStateMachine.State.ATTACK \
			and to_state != EnemyStateMachine.State.ATTACK:
		_stop_attack_hitbox()
	match to_state:
		EnemyStateMachine.State.ATTACK:
			attack_timer = 0.0
			_attack_performed = false
			_attack_hitbox_live = false
			attack_hitbox.deactivate()
			_face_target()
		EnemyStateMachine.State.HURT:
			_stop_attack_hitbox()


## Безопасно гасит хитбокс: `active` сразу, `monitoring` — отложенно,
## потому что урон/фаза могут прийти во время flushing physics queries.
func _stop_attack_hitbox() -> void:
	if attack_hitbox != null:
		attack_hitbox.active = false
		attack_hitbox.set_deferred("monitoring", false)
	_attack_hitbox_live = false


func _apply_incoming_knockback(damage: Damage) -> void:
	if data == null:
		return
	var factor: float = 1.0 - clampf(data.knockback_resistance, 0.0, 1.0)
	velocity += damage.knockback * factor


func _tick_phase_invulnerability(delta: float) -> void:
	if _phase_invulnerable_left <= 0.0:
		return
	_phase_invulnerable_left = maxf(_phase_invulnerable_left - delta, 0.0)
	if _phase_invulnerable_left <= 0.0 and not is_dead:
		hurtbox.set_invulnerable(false)


func _start_hit_flash(damage: Damage) -> void:
	if visual == null:
		return
	_flash_time_left = clampf(damage.hit_flash_duration, 0.0, Damage.HIT_FLASH_MAX_SEC)
	visual.modulate = Damage.FLASH_COLOR


func _tick_hit_flash(delta: float) -> void:
	if _flash_time_left <= 0.0:
		return
	_flash_time_left = maxf(_flash_time_left - delta, 0.0)
	if _flash_time_left <= 0.0 and not is_dead and visual != null and data != null:
		visual.modulate = data.get_body_color()


func _apply_data() -> void:
	if visual != null:
		var texture := PlaceholderTexture2D.new()
		texture.size = data.body_size
		visual.texture = texture
		visual.modulate = data.get_body_color()
		visual.scale = Vector2.ONE
	_set_rect_shape(body_shape, data.body_size)
	_set_rect_shape(hurt_shape, data.hurtbox_size)
	var phase: BossPhaseData = _current_phase()
	if phase != null:
		_apply_attack_shape(phase)


func _apply_attack_shape(phase: BossPhaseData) -> void:
	if phase == null or attack_shape == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(phase.attack_size.x, 1.0), maxf(phase.attack_size.y, 1.0))
	# Смена фазы может прийти из обработчика урона (physics flush) — форма
	# Area2D меняется отложенно, чтобы не трогать physics server в этот момент.
	attack_shape.set_deferred("shape", rect)


func _set_rect_shape(node: CollisionShape2D, size: Vector2) -> void:
	if node == null:
		return
	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	node.shape = rect


func _configure_combat() -> void:
	hurtbox.hurt_layer = CombatLayers.ENEMY_HURTBOX
	hurtbox.collision_layer = CombatLayers.ENEMY_HURTBOX
	hurtbox.collision_mask = 0
	hurtbox.apply_reactions = false
	hurtbox.set_invulnerable(false)
	if not hurtbox.damaged.is_connected(_on_hurtbox_damaged):
		hurtbox.damaged.connect(_on_hurtbox_damaged)

	attack_hitbox.hit_layer = CombatLayers.ENEMY_HITBOX
	attack_hitbox.target_mask = CombatLayers.PLAYER_HURTBOX
	attack_hitbox.collision_layer = CombatLayers.ENEMY_HITBOX
	attack_hitbox.collision_mask = CombatLayers.PLAYER_HURTBOX
	attack_hitbox.start_active = false
	attack_hitbox.deactivate()

	collision_layer = CombatLayers.ENEMY_BODY
	collision_mask = CombatLayers.WORLD
