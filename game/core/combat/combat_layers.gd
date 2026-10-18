class_name CombatLayers
extends RefCounted
## CombatLayers — единый источник битовых масок боя (T-10).
##
## Совпадает с именами слоёв в `project.godot` (`[layer_names]`):
##   1 world, 2 player, 3 enemy, 4 player_hitbox, 5 enemy_hitbox,
##   6 player_hurtbox, 7 enemy_hurtbox, 8 interactable, 9 hazard, 10 pickup.
##
## Правило: Hitbox живёт на слое атакующего (`*_hitbox`) и маскирует
## hurtbox цели (`*_hurtbox`); Hurtbox только выставляет свой слой
## (`collision_mask = 0`) и не сканирует мир.

const WORLD: int = 1 << 0
const PLAYER_BODY: int = 1 << 1
const ENEMY_BODY: int = 1 << 2
const PLAYER_HITBOX: int = 1 << 3
const ENEMY_HITBOX: int = 1 << 4
const PLAYER_HURTBOX: int = 1 << 5
const ENEMY_HURTBOX: int = 1 << 6
const INTERACTABLE: int = 1 << 7
const HAZARD: int = 1 << 8
const PICKUP: int = 1 << 9
