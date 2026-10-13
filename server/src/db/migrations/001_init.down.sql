-- 001_init.down.sql — откат начальной схемы (обратная миграция для 001_init.sql).
-- Порядок удаления — обратный зависимостям FK (сначала дочерние таблицы, затем users).
-- schema_migrations чистит runner (migrate.ts), поэтому здесь её не трогаем.

DROP INDEX IF EXISTS idx_note_tags_tag;
DROP INDEX IF EXISTS idx_notes_user_updated;
DROP INDEX IF EXISTS idx_sessions_user;

DROP TABLE IF EXISTS note_tags;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS notes;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS users;
