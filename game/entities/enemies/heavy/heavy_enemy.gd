class_name HeavyEnemy
extends Enemy
## HeavyEnemy — тяжёлый враг (T-12). Паттерн: медленный, высокое HP/poise,
## широкий удар с долгим telegraph. Во время замаха «вкапывается» и не
## получает отбрасывание (супер-армор), но урон и вспышка проходят всегда.


func _apply_incoming_knockback(damage: Damage) -> void:
	if fsm != null and fsm.current == EnemyStateMachine.State.ATTACK:
		return
	super(damage)
