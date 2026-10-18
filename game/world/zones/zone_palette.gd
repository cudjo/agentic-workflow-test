class_name ZonePalette
extends Resource
## Палитра зоны (DESIGN §8.6): цвета фона, земли/платформ, акцента и опасности.
## Сцена зоны применяет палитру к фону, TileMapLayer'ам и акцентным props,
## чтобы один и тот же тайлсет-заглушка перекрашивался под конкретную зону.

@export var background: Color = Color("1a1f2e")
@export var ground: Color = Color("4a4a4f")
@export var accent: Color = Color("c08a3e")
@export var hazard: Color = Color("7a2a24")
