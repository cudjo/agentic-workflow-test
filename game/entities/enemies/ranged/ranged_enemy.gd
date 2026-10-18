class_name RangedEnemy
extends Enemy
## RangedEnemy — дальний враг (T-12). Паттерн: держит `preferred_distance`,
## отступает при сближении и стреляет снарядом вместо ближнего хитбокса.
## Снаряд летит по прямой из данных и наносит урон через то же боевое ядро
## T-10 (Hitbox → player_hurtbox).


func _activate_attack() -> void:
	if data == null or data.projectile_scene == null:
		push_error("RangedEnemy: projectile_scene is missing for '%s'" % data.id)
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	var projectile: EnemyProjectile = data.projectile_scene.instantiate() as EnemyProjectile
	if projectile == null:
		push_error("RangedEnemy: projectile scene is not an EnemyProjectile")
		return

	var direction := Vector2(float(facing), 0.0)
	var spawn_global: Vector2 = global_position + direction * (data.body_size.x * 0.5 + 4.0)
	parent.add_child(projectile)
	projectile.global_position = spawn_global
	var payload: Damage = Damage.create(
		data.attack_damage,
		Vector2.ZERO,
		balance.hit_flash_duration
	)
	projectile.setup(
		payload,
		data.attack_knockback * balance.knockback_scale,
		direction,
		data.projectile_speed,
		data.projectile_lifetime
	)
