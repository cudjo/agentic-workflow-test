class_name Enemy
extends CharacterBody2D
## Enemy — база врага (T-12): CharacterBody2D + поведенческий FSM
## patrol/chase/attack/hurt/death, боевое ядро из T-10 (Hitbox/Hurtbox/Damage).
##
## Параметры (HP, скорости, урон, радиусы, тайминги патруля/атаки) —
## `data/enemies/*.tres` (`EnemyData`). Общие боевые тайминги (вспышка,
## отшатывание, анимация смерти, отбрасывание) — `balancing.tres`.
## Слои — только `CombatLayers`; враг не рисует UI и не хранит состояние
## забега. Смерть/урон транслируются в `EventBus`.
##
## Движение — простые прямые/платформенные пути без навмеша (PLAN T-12):
## поворот на стене и у края платформы (RayCast2D), жёсткий leash от точки
## спавна и watchdog против залипания. Vertical movement — ручная гравитация.

signal died(enemy: Enemy)
## Активная фаза атаки началась (telegraph закончился). Потребители: звук
## (T-34), тесты паттернов; UI не подписывается.
signal attack_performed(enemy: Enemy)

const BALANCE_PATH: String = "res://data/balance/balancing.tres"
const PLAYER_GROUP: StringName = &"player"
## Минимальное смещение за тик, ниже которого враг считается застрявшим.
const STUCK_MIN_MOVE_PX: float = 0.1

@export var data: EnemyData
@export var balance: BalancingParams
## Начальное направление патруля: -1 — влево, 1 — вправо.
@export var initial_facing: int = -1

var fsm: EnemyStateMachine
var hp: float = 0.0
var facing: int = -1
## Точка спавна — центр патрульной зоны и leash.
var home_position: Vector2 = Vector2.ZERO
var target: Node2D = null
var attack_timer: float = 0.0
var attack_cooldown_left: float = 0.0
var patrol_wait_left: float = 0.0
var is_dead: bool = false

var _attack_hitbox_live: bool = false
var _death_elapsed: float = 0.0
var _stuck_time: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _flash_time_left: float = 0.0
## T-35: не более 3 вспышек урона/с на врага; в режиме «Без мигания» — 0.
var _flash_governor := FlashGovernor.new()
var flash_applied_count: int = 0

@onready var visual: Sprite2D = $Visual
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var attack_hitbox: Hitbox = $Hitbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var hurt_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var attack_shape: CollisionShape2D = $Hitbox/CollisionShape2D
@onready var ledge_ray: RayCast2D = $LedgeRay
@onready var wall_ray: RayCast2D = $WallRay


func _ready() -> void:
	add_to_group(&"enemies")
	if data == null:
		push_error("Enemy: data resource is missing on %s" % name)
		set_physics_process(false)
		return
	if balance == null:
		balance = GameState.balance if GameState != null else null
	if balance == null:
		balance = load(BALANCE_PATH) as BalancingParams
	if balance == null:
		push_error("Enemy: balancing resource is missing at %s" % BALANCE_PATH)
		set_physics_process(false)
		return
	if not data.is_valid():
		push_error("Enemy: invalid EnemyData '%s'" % data.id)

	hp = data.max_hp
	home_position = global_position
	_last_position = global_position
	facing = -1 if initial_facing < 0 else 1
	_apply_data()
	_configure_combat()
	fsm = _new_state_machine()
	_connect_state_machine()
	_set_facing(facing)


func _physics_process(delta: float) -> void:
	if data == null or balance == null or fsm == null:
		return

	fsm.tick(delta)
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)

	match fsm.current:
		EnemyStateMachine.State.PATROL:
			_tick_patrol(delta)
		EnemyStateMachine.State.CHASE:
			_tick_chase(delta)
		EnemyStateMachine.State.ATTACK:
			_tick_attack(delta)
		EnemyStateMachine.State.HURT:
			_tick_hurt(delta)
		EnemyStateMachine.State.DEATH:
			_tick_death(delta)

	_tick_hit_flash(delta)

	if fsm.current == EnemyStateMachine.State.DEATH:
		velocity = Vector2.ZERO
		return

	velocity.y += balance.get_gravity() * delta
	move_and_slide()
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
	_clamp_to_leash()
	_update_stuck(delta)


# ------------------------------------------------------------------------------
# FSM state ticks
# ------------------------------------------------------------------------------

func _tick_patrol(delta: float) -> void:
	if _can_detect_target():
		if fsm.request_state(EnemyStateMachine.State.CHASE):
			return

	if patrol_wait_left > 0.0:
		patrol_wait_left = maxf(patrol_wait_left - delta, 0.0)
		velocity.x = 0.0
		return

	_update_rays(facing)
	if _should_turn_patrol():
		_turn_around()
		return

	velocity.x = float(facing) * data.patrol_speed


func _tick_chase(_delta: float) -> void:
	if not _can_detect_target() or target == null:
		_lose_target()
		return
	if absf(global_position.x - home_position.x) > data.leash_radius:
		_lose_target()
		return

	var to_target: Vector2 = target.global_position - global_position
	var dx: float = to_target.x
	_set_facing(1 if dx >= 0.0 else -1)
	var distance: float = to_target.length()
	var too_close: bool = data.preferred_distance > 0.0 and distance < data.preferred_distance

	if not too_close and distance <= data.attack_radius and attack_cooldown_left <= 0.0:
		if fsm.request_state(EnemyStateMachine.State.ATTACK):
			return

	var move_dir: int = 0
	if too_close:
		move_dir = -1 if dx > 0.0 else 1
	elif distance > data.attack_radius:
		move_dir = 1 if dx > 0.0 else -1

	if move_dir != 0 and _can_step(move_dir):
		velocity.x = float(move_dir) * data.chase_speed
	else:
		velocity.x = 0.0


func _tick_attack(delta: float) -> void:
	attack_timer += delta
	velocity.x = 0.0
	_attack_tick(delta)

	var active_start: float = maxf(data.attack_windup, 0.0)
	var active_end: float = active_start + maxf(data.attack_active, 0.0)
	if (
		not _attack_hitbox_live
		and attack_timer >= active_start
		and attack_timer < active_end
	):
		_activate_attack()
		_attack_hitbox_live = true
		attack_performed.emit(self)

	if _attack_hitbox_live and attack_timer >= active_end:
		attack_hitbox.deactivate()
		_attack_hitbox_live = false

	if attack_timer >= data.get_attack_total_time():
		attack_hitbox.deactivate()
		_attack_hitbox_live = false
		attack_cooldown_left = data.attack_cooldown
		if _can_detect_target() and absf(global_position.x - home_position.x) <= data.leash_radius:
			fsm.force_state(EnemyStateMachine.State.CHASE)
		else:
			_lose_target()


func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(
		velocity.x,
		0.0,
		maxf(balance.enemy_knockback_friction, 0.0) * delta
	)
	if fsm.time_in_state < balance.t_hurt:
		return
	if _can_detect_target():
		fsm.force_state(EnemyStateMachine.State.CHASE)
	else:
		_lose_target()


func _tick_death(delta: float) -> void:
	_death_elapsed += delta
	var fade_duration: float = maxf(balance.enemy_death_duration, 0.001)
	var progress: float = clampf(_death_elapsed / fade_duration, 0.0, 1.0)
	if visual != null:
		var color: Color = data.get_body_color()
		color.a = 1.0 - progress
		visual.modulate = color
		visual.scale = Vector2(1.0 + 0.15 * progress, 1.0 - 0.35 * progress)
	if _death_elapsed >= _get_death_duration():
		_finish_death()


# ------------------------------------------------------------------------------
# Virtual hooks (subtypes: swift/heavy/ranged/undead)
# ------------------------------------------------------------------------------

## Дополнительное поведение в активной фазе (swift — рывок).
func _attack_tick(_delta: float) -> void:
	pass


## Включение атаки: база — ближний хитбокс, ranged переопределяет снарядом.
func _activate_attack() -> void:
	attack_hitbox.position = Vector2(
		data.attack_offset.x * float(facing),
		data.attack_offset.y
	)
	var payload: Damage = Damage.create(
		data.attack_damage,
		Vector2.ZERO,
		balance.hit_flash_duration
	)
	var knockback_force: float = data.attack_knockback * balance.knockback_scale
	attack_hitbox.clear_hits()
	attack_hitbox.activate(payload, knockback_force, Vector2(float(facing), 0.0))


## Отбрасывание от входящего урона; heavy гасит его во время замаха.
func _apply_incoming_knockback(damage: Damage) -> void:
	var factor: float = 1.0 - clampf(data.knockback_resistance, 0.0, 1.0)
	velocity += damage.knockback * factor


## Полная длительность смерти (undead добавляет время «лежания»).
func _get_death_duration() -> float:
	return maxf(balance.enemy_death_duration, 0.0)


## Возрождение (undead). База не возрождается.
func _try_revive() -> bool:
	return false


# ------------------------------------------------------------------------------
# Damage / death (T-10 combat core)
# ------------------------------------------------------------------------------

func _on_hurtbox_damaged(damage: Damage) -> void:
	if is_dead or damage == null or fsm == null:
		return
	hp = maxf(hp - damage.amount, 0.0)
	# Вспышка попадания — в том же physics-кадре, что и урон (<= 100 ms).
	_start_hit_flash(damage)
	_apply_incoming_knockback(damage)

	if hp <= 0.0:
		_die()
		return

	if damage.amount >= data.poise:
		if fsm.current == EnemyStateMachine.State.HURT:
			fsm.time_in_state = 0.0
		else:
			fsm.request_state(EnemyStateMachine.State.HURT)


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	fsm.force_state(EnemyStateMachine.State.DEATH)
	_death_elapsed = 0.0
	_attack_hitbox_live = false
	attack_hitbox.deactivate()
	hurtbox.set_invulnerable(true)
	hurtbox.set_deferred("monitorable", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	velocity = Vector2.ZERO


func _finish_death() -> void:
	if _try_revive():
		return
	died.emit(self)
	EventBus.enemy_died.emit(data.id, global_position)
	queue_free()


# ------------------------------------------------------------------------------
# Public queries (tests, spawner, future progression)
# ------------------------------------------------------------------------------

func get_state_name() -> StringName:
	if fsm == null:
		return &""
	return fsm.get_state_name()


func get_health_ratio() -> float:
	if data == null or data.max_hp <= 0.0:
		return 0.0
	return clampf(hp / data.max_hp, 0.0, 1.0)


## Переустановка точки спавна (spawner/телепорт зоны).
func set_home_position(position: Vector2) -> void:
	home_position = position
	_last_position = position


# ------------------------------------------------------------------------------
# Internals
# ------------------------------------------------------------------------------

func _new_state_machine() -> EnemyStateMachine:
	return EnemyStateMachine.new()


func _connect_state_machine() -> void:
	fsm.state_changed.connect(_on_state_changed)


func _on_state_changed(from_state: EnemyStateMachine.State, to_state: EnemyStateMachine.State) -> void:
	if from_state == EnemyStateMachine.State.ATTACK and to_state != EnemyStateMachine.State.ATTACK:
		attack_hitbox.deactivate()
		_attack_hitbox_live = false
	match to_state:
		EnemyStateMachine.State.ATTACK:
			attack_timer = 0.0
			_attack_hitbox_live = false
			attack_hitbox.deactivate()
			_face_target()
		EnemyStateMachine.State.HURT:
			attack_hitbox.deactivate()
			_attack_hitbox_live = false
		EnemyStateMachine.State.PATROL:
			patrol_wait_left = 0.0


func _can_detect_target() -> bool:
	if target == null or not is_instance_valid(target):
		target = _find_target()
	if target == null:
		return false
	var dx: float = absf(target.global_position.x - global_position.x)
	var dy: float = absf(target.global_position.y - global_position.y)
	return dx <= data.detect_radius and dy <= data.vertical_detect_radius


func _find_target() -> Node2D:
	if not is_inside_tree():
		return null
	var player: Node = get_tree().get_first_node_in_group(PLAYER_GROUP)
	return player as Node2D


func _lose_target() -> void:
	target = null
	fsm.force_state(EnemyStateMachine.State.PATROL)
	patrol_wait_left = 0.0


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
	if attack_hitbox != null and data != null:
		attack_hitbox.position = Vector2(
			data.attack_offset.x * float(facing),
			data.attack_offset.y
		)


func _should_turn_patrol() -> bool:
	if is_on_wall():
		return true
	if absf(global_position.x - home_position.x) >= data.patrol_range:
		return true
	if is_on_floor() and not ledge_ray.is_colliding():
		return true
	return false


func _turn_around() -> void:
	velocity.x = 0.0
	patrol_wait_left = data.patrol_pause
	_set_facing(-facing)


## Проверка шага: стена впереди или край платформы останавливают врага.
func _can_step(direction: int) -> bool:
	if direction == 0:
		return false
	_update_rays(direction)
	if wall_ray.is_colliding():
		return false
	if is_on_floor() and not ledge_ray.is_colliding():
		return false
	return true


func _update_rays(direction: int) -> void:
	if data == null or ledge_ray == null or wall_ray == null:
		return
	var half_width: float = data.body_size.x * 0.5
	var dir: float = 1.0 if direction >= 0 else -1.0
	ledge_ray.position = Vector2(dir * (half_width + 1.0), 0.0)
	ledge_ray.target_position = Vector2(0.0, data.body_size.y * 0.5 + 4.0)
	wall_ray.position = Vector2.ZERO
	wall_ray.target_position = Vector2(dir * (half_width + 3.0), 0.0)
	ledge_ray.force_raycast_update()
	wall_ray.force_raycast_update()


## Жёсткая граница зоны: AI не выходит за leash даже при погоне.
func _clamp_to_leash() -> void:
	if data == null or fsm == null or fsm.current == EnemyStateMachine.State.DEATH:
		return
	var offset_x: float = global_position.x - home_position.x
	if absf(offset_x) <= data.leash_radius:
		return
	global_position.x = home_position.x + signf(offset_x) * data.leash_radius
	velocity.x = 0.0
	if fsm.current == EnemyStateMachine.State.CHASE:
		_lose_target()


## Watchdog: если враг не сдвинулся, пока должен идти, — разворот/патруль.
func _update_stuck(delta: float) -> void:
	if fsm.current != EnemyStateMachine.State.PATROL \
			and fsm.current != EnemyStateMachine.State.CHASE:
		_stuck_time = 0.0
		_last_position = global_position
		return
	var moved: float = global_position.distance_to(_last_position)
	_last_position = global_position
	if moved < STUCK_MIN_MOVE_PX:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time < balance.enemy_stuck_timeout:
		return
	_stuck_time = 0.0
	if fsm.current == EnemyStateMachine.State.CHASE:
		_lose_target()
	_turn_around()


## Вспышка включена в кадре урона; тикает локально, поэтому серия попаданий
## и анимация смерти не «залипают» в белом цвете (в отличие от async-вспышки).
func _start_hit_flash(damage: Damage) -> void:
	if visual == null:
		return
	# T-35/DESIGN §9.3: «Без мигания» и лимит 3/с — вспышка пропускается,
	# тело остаётся в обычном цвете (урон при этом применяется).
	if _is_no_flash() or not _flash_governor.try_flash(_now_sec()):
		_flash_time_left = 0.0
		visual.modulate = data.get_body_color()
		return
	flash_applied_count += 1
	_flash_time_left = clampf(damage.hit_flash_duration, 0.0, Damage.HIT_FLASH_MAX_SEC)
	visual.modulate = Damage.FLASH_COLOR


func _tick_hit_flash(delta: float) -> void:
	if _flash_time_left <= 0.0:
		return
	_flash_time_left = maxf(_flash_time_left - delta, 0.0)
	if _flash_time_left <= 0.0 and not is_dead and visual != null:
		visual.modulate = data.get_body_color()


func _now_sec() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _is_no_flash() -> bool:
	var config := get_node_or_null("/root/Config")
	return config != null and bool(config.get("no_flash"))


func _apply_data() -> void:
	if visual != null:
		var texture := PlaceholderTexture2D.new()
		texture.size = data.body_size
		visual.texture = texture
		visual.modulate = data.get_body_color()
		visual.scale = Vector2.ONE
	_set_rect_shape(body_shape, data.body_size)
	_set_rect_shape(hurt_shape, data.hurtbox_size)
	_set_rect_shape(attack_shape, data.attack_size)
	if ledge_ray != null:
		ledge_ray.collision_mask = CombatLayers.WORLD
	if wall_ray != null:
		wall_ray.collision_mask = CombatLayers.WORLD


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

	ledge_ray.collision_mask = CombatLayers.WORLD
	wall_ray.collision_mask = CombatLayers.WORLD
