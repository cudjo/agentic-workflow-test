class_name BossRewardData
extends Resource
## BossRewardData — награда за победу над боссом (T-30, EC-09).
##
## Награда не привязана к UI: `GameState` кладёт её в очередь и выдаёт
## (добавляет золото, эмитит `EventBus.boss_reward_granted`) сразу после
## победы, если игрок жив, либо при следующем входе в зону, если игрок погиб
## до получения (EC-09).

@export var id: StringName = &""
## Золото/валюта, добавляемая игроку.
@export var gold: int = 0


func is_valid() -> bool:
	return id != &"" and gold >= 0
