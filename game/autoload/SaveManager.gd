extends Node
## SaveManager — 3 слота в user://saves/slot_{1..3}.json, checksum SHA-256,
## атомарная запись (tmp + rename), миграции по schema_version (T-25).
## Заглушка каркаса (T-01); сериализация GameState — задача T-25.
