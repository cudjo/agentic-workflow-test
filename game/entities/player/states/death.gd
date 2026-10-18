extends PlayerState
## Death — terminal state. Interrupts any action instantly (EC-01) and emits
## EventBus.player_died; the death screen / corpse run is handled by T-26.


func enter(_previous: StringName) -> void:
	super.enter(_previous)
	player.velocity = Vector2.ZERO
	EventBus.player_died.emit()


func physics_update(_delta: float) -> void:
	player.velocity = Vector2.ZERO


func uses_gravity() -> bool:
	return false
