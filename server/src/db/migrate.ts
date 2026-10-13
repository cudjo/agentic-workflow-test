/**
 * db/migrate.ts — runner миграций (PLAN §2, T-01).
 *
 * Применяет `migrations/*.sql` по порядку имён, учитывая применённые в таблице
 * `schema_migrations`. Идемпотентен: повторный запуск не дублирует и не падает.
 * Обратим: `--down` откатывает последнюю миграцию через парный `*.down.sql`.
 * Каждая миграция применяется в отдельной транзакции (атомарно: DDL + запись версии).
 *
 * CLI:
 *   npm run migrate                 # применить все неприменённые
 *   npm run migrate -- --down       # откатить последнюю
 *   npm run migrate -- --status     # показать применённые
 *   DATABASE_PATH=... npm run migrate
 */
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import type { DatabaseSync } from 'node:sqlite';
import { nowIso, openDatabase, resolveDatabasePath, transaction } from './client.js';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

/** Каталог с SQL-файлами миграций (в git, PLAN §2). */
export const MIGRATIONS_DIR = resolve(MODULE_DIR, 'migrations');

export interface Migration {
  /** Идентификатор версии — имя файла, например `001_init.sql`. Первичный ключ schema_migrations. */
  id: string;
  /** Человекочитаемое имя без расширения. */
  name: string;
  /** Тело SQL. */
  sql: string;
}

export interface AppliedMigration {
  id: string;
  name: string;
  applied_at: string;
}

/** Создаёт служебную таблицу учёта применённых миграций. */
export function ensureMigrationsTable(db: DatabaseSync): void {
  db.exec(
    `CREATE TABLE IF NOT EXISTS schema_migrations (
       id         TEXT PRIMARY KEY,
       name       TEXT NOT NULL,
       applied_at TEXT NOT NULL
     )`,
  );
}

/** Перечисляет up-миграции в порядке применения (лексикографически по имени файла). */
export function listMigrations(dir: string = MIGRATIONS_DIR): Migration[] {
  return readdirSync(dir)
    .filter((file) => file.endsWith('.sql') && !file.endsWith('.down.sql'))
    .sort()
    .map((file) => ({
      id: file,
      name: file.replace(/\.sql$/, ''),
      sql: readFileSync(join(dir, file), 'utf8'),
    }));
}

/** Возвращает id применённых миграций в порядке применения. */
export function getAppliedMigrations(db: DatabaseSync): AppliedMigration[] {
  ensureMigrationsTable(db);
  const rows = db
    .prepare(`SELECT id, name, applied_at FROM schema_migrations ORDER BY id ASC`)
    .all() as unknown as AppliedMigration[];
  return rows;
}

/**
 * Применяет все неприменённые миграции. Возвращает id тех, что реально применились
 * (повторный вызов на актуальной БД → `[]`).
 */
export function migrateUp(db: DatabaseSync, dir: string = MIGRATIONS_DIR): string[] {
  ensureMigrationsTable(db);
  const applied = new Set(getAppliedMigrations(db).map((m) => m.id));
  const record = db.prepare(
    `INSERT INTO schema_migrations (id, name, applied_at) VALUES (?, ?, ?)`,
  );
  const ran: string[] = [];

  for (const migration of listMigrations(dir)) {
    if (applied.has(migration.id)) continue;
    transaction(db, () => {
      db.exec(migration.sql);
      record.run(migration.id, migration.name, nowIso());
    });
    ran.push(migration.id);
  }
  return ran;
}

/**
 * Откатывает `steps` последних миграций (по умолчанию одну), исполняя парный `*.down.sql`.
 * Возвращает id откаченных миграций (свежие сначала).
 */
export function migrateDown(db: DatabaseSync, dir: string = MIGRATIONS_DIR, steps = 1): string[] {
  ensureMigrationsTable(db);
  if (!Number.isFinite(steps) || steps < 1) return [];

  const rows = db
    .prepare(`SELECT id, name FROM schema_migrations ORDER BY id DESC LIMIT ?`)
    .all(steps) as unknown as Array<Pick<AppliedMigration, 'id' | 'name'>>;
  const unrecord = db.prepare(`DELETE FROM schema_migrations WHERE id = ?`);
  const rolled: string[] = [];

  for (const row of rows) {
    const downFile = join(dir, `${row.name}.down.sql`);
    const sql = readFileSync(downFile, 'utf8');
    transaction(db, () => {
      db.exec(sql);
      unrecord.run(row.id);
    });
    rolled.push(row.id);
  }
  return rolled;
}

interface CliOptions {
  down: boolean;
  status: boolean;
  steps: number;
  db?: string;
}

function parseArgs(argv: string[]): CliOptions {
  const opts: CliOptions = { down: false, status: false, steps: 1 };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i] ?? '';
    if (arg === '--down') opts.down = true;
    else if (arg === '--up') opts.down = false;
    else if (arg === '--status') opts.status = true;
    else if (arg === '--db') opts.db = argv[++i];
    else if (arg.startsWith('--db=')) opts.db = arg.slice('--db='.length);
    else if (arg === '--steps') opts.steps = Number.parseInt(argv[++i] ?? '1', 10) || 1;
  }
  return opts;
}

/** Точка входа CLI. Возвращает код выхода. */
export function main(argv: string[] = process.argv.slice(2)): number {
  const opts = parseArgs(argv);
  const dbPath = resolveDatabasePath(opts.db);
  const db = openDatabase(opts.db);
  const label = dbPath === ':memory:' ? ':memory:' : dbPath;

  try {
    if (opts.status) {
      const applied = getAppliedMigrations(db);
      console.log(`[migrate] database: ${label}`);
      if (applied.length === 0) console.log('[migrate] никаких миграций не применено');
      for (const m of applied) console.log(`[migrate]   applied ${m.name} @ ${m.applied_at}`);
      return 0;
    }

    if (opts.down) {
      const rolled = migrateDown(db, MIGRATIONS_DIR, opts.steps);
      console.log(
        rolled.length === 0
          ? `[migrate] ${label}: нечего откатывать`
          : `[migrate] ${label}: откачено ${rolled.length} — ${rolled.join(', ')}`,
      );
      return 0;
    }

    const ran = migrateUp(db);
    console.log(
      ran.length === 0
        ? `[migrate] ${label}: схема актуальна, применять нечего`
        : `[migrate] ${label}: применено ${ran.length} — ${ran.join(', ')}`,
    );
    return 0;
  } catch (error) {
    console.error(`[migrate] ОШИБКА: ${error instanceof Error ? error.message : String(error)}`);
    return 1;
  } finally {
    db.close();
  }
}

const invokedDirectly =
  typeof process.argv[1] === 'string' && pathToFileURL(process.argv[1]).href === import.meta.url;

if (invokedDirectly) {
  process.exitCode = main();
}
