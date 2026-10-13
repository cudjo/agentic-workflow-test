/**
 * app.ts — сборка Fastify-приложения (PLAN §2).
 *
 * Здесь только инфраструктура: конфиг, подключение БД, CORS, роуты, централизованная
 * обработка ошибок и 404. Бизнес-логика — в сервисах/роутах (T-03..T-05).
 *
 * Гарантии:
 *   * ошибки — единый JSON `{error:{code,message,field?}}` (§3.2), без stack;
 *   * логгер редактирует пароли/токены/cookie (NFR-9/A9);
 *   * `buildApp` не вызывает `listen` — это делает entrypoint (`index.ts`), тесты используют `inject`.
 */
import cors from '@fastify/cors';
import Fastify, { type FastifyInstance } from 'fastify';
import type { DatabaseSync } from 'node:sqlite';
import { loadConfig, type Config } from './config.js';
import { openDatabase, prepareStatements, type Statements } from './db/client.js';
import { migrateUp } from './db/migrate.js';
import { errorBody, toHttpError } from './lib/errors.js';
import { healthRoutes } from './routes/health.js';

declare module 'fastify' {
  interface FastifyInstance {
    /** Загруженный конфиг (env). */
    config: Config;
    /** Открытое соединение SQLite. */
    db: DatabaseSync;
    /** Подготовленные statements (db/client.ts). */
    stmts: Statements;
  }
}

/** Пути pino, значение которых никогда не попадает в лог (NFR-9/A9). */
export const REDACT_PATHS: string[] = [
  'password',
  'passwordHash',
  'password_hash',
  'token',
  'csrfToken',
  'csrf_token',
  '*.password',
  '*.passwordHash',
  '*.password_hash',
  '*.token',
  '*.csrfToken',
  '*.csrf_token',
  'req.headers.cookie',
  'req.headers.authorization',
  'req.headers["x-csrf-token"]',
  'res.headers["set-cookie"]',
  'headers.cookie',
  'headers.authorization',
];

export interface BuildAppOptions {
  /** Готовый конфиг (иначе `loadConfig()`). */
  config?: Config;
  /** Внешнее соединение БД (тесты: `:memory:`); иначе открывается по `config.databasePath`. */
  db?: DatabaseSync;
  /** `false` — отключить логгер (тесты). */
  logger?: boolean;
  /** Поток вывода лога (тесты перехватывают вывод). */
  loggerStream?: NodeJS.WritableStream;
  /**
   * Применять неприменённые миграции при старте (идемпотентно, T-01).
   * По умолчанию `true` — сервер поднимается на чистой БД; `false` — схема управляется извне.
   */
  autoMigrate?: boolean;
}

export async function buildApp(options: BuildAppOptions = {}): Promise<FastifyInstance> {
  const config = options.config ?? loadConfig();

  const logger =
    options.logger === false
      ? false
      : {
          level: config.logLevel,
          redact: { paths: REDACT_PATHS, censor: '[redacted]' },
          ...(options.loggerStream ? { stream: options.loggerStream } : {}),
        };

  const app = Fastify({ logger });

  // БД: соединение живёт всё время работы приложения; закрываем в onClose (кроме переданного извне).
  const db = options.db ?? openDatabase(config.databasePath);
  if (options.autoMigrate !== false) {
    // Идемпотентно: на актуальной схеме не делает ничего (T-01).
    migrateUp(db);
  }
  app.decorate('config', config);
  app.decorate('db', db);
  app.decorate('stmts', prepareStatements(db));
  if (!options.db) {
    app.addHook('onClose', async () => {
      db.close();
    });
  }

  // CORS: в dev фронтенд на 5173 ходит с credentials (cookie-сессия, PLAN §4.2).
  await app.register(cors, {
    origin: config.corsOrigin,
    credentials: true,
    methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'X-CSRF-Token'],
  });

  await app.register(healthRoutes);

  app.setNotFoundHandler((request, reply) => {
    reply.code(404).send(errorBody('NOT_FOUND', `Маршрут ${request.method} ${request.url} не найден`));
  });

  app.setErrorHandler((error, request, reply) => {
    const { statusCode, body } = toHttpError(error);
    if (statusCode >= 500) {
      // Полная ошибка (со stack) — только в лог, не в ответ (NFR-9).
      request.log.error({ err: error }, 'unhandled server error');
    } else {
      request.log.warn({ code: body.error.code, statusCode }, body.error.message);
    }
    reply.code(statusCode).send(body);
  });

  return app;
}
