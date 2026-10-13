/**
 * config.ts — конфигурация сервера из переменных окружения (PLAN §2, §4).
 *
 * Правила:
 *   * секреты приходят только из env (NFR-8) — в коде нет значений по умолчанию для секретов;
 *     `SESSION_SECRET` опционален и не влияет на безопасность (см. ниже);
 *   * `Cookie: Secure` включается по умолчанию в production (NFR-10), в dev/test — выкл; явный
 *     `COOKIE_SECURE` перекрывает дефолт;
 *   * все значения типизированы и валидируются на границе (порт, булевы флаги).
 */
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DEFAULT_DB_PATH } from './db/client.js';

export type NodeEnv = 'development' | 'production' | 'test';

const MODULE_DIR = dirname(fileURLToPath(import.meta.url));

export interface Config {
  nodeEnv: NodeEnv;
  isProduction: boolean;
  /** Адрес прослушивания. По умолчанию только localhost (dev); в контейнере — 0.0.0.0. */
  host: string;
  port: number;
  databasePath: string;
  /**
   * Опциональный секрет окружения (PLAN §4.7). **Не** используется для целостности сессии:
   * токен сессии — opaque (`randomBytes(32)`), в БД хранится только его SHA-256, подпись не нужна;
   * CSRF — сверка `csrf_token` через `timingSafeEqual`. Значение переносится в конфиг как есть
   * (совместимость с деплой-окружениями), отсутствие — не ошибка ни в одном режиме.
   */
  sessionSecret?: string;
  /**
   * Флаг `Secure` для cookie сессии. Дефолт: `NODE_ENV === 'production'` (NFR-10),
   * явный `COOKIE_SECURE` перекрывает (нужен для локального прод-HTTP запуска).
   */
  cookieSecure: boolean;
  corsOrigin: string;
  logLevel: string;
  /** Каталог собранного фронтенда (`web/dist`), который раздаёт Fastify (T-12). */
  staticDir: string;
}

export const DEFAULT_PORT = 3000;
export const DEFAULT_HOST = '127.0.0.1';
/** Dev-ориджин Vite (PLAN §2: фронтенд-dev 5173). */
export const DEFAULT_CORS_ORIGIN = 'http://localhost:5173';
export const DEFAULT_LOG_LEVEL = 'info';
/** Собранный фронтенд по умолчанию: `web/dist` относительно корня репозитория (T-12). */
export const DEFAULT_STATIC_DIR = resolve(MODULE_DIR, '..', '..', 'web', 'dist');

function parseNodeEnv(raw: string | undefined): NodeEnv {
  if (raw === 'production' || raw === 'test') return raw;
  return 'development';
}

function parsePort(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === '') return DEFAULT_PORT;
  const port = Number.parseInt(raw, 10);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`Некорректный PORT: ${raw}`);
  }
  return port;
}

function parseBool(raw: string | undefined, fallback: boolean): boolean {
  if (raw === undefined || raw.trim() === '') return fallback;
  const value = raw.trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

/** Загружает и валидирует конфиг. `env` инъектируется для тестов. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const nodeEnv = parseNodeEnv(env.NODE_ENV);
  const isProduction = nodeEnv === 'production';

  // Секрет опционален во всех режимах: сессии — opaque token + SHA-256 в БД (подпись не нужна),
  // CSRF — сверка csrf_token через timingSafeEqual (PLAN §4.7).
  const sessionSecret = env.SESSION_SECRET?.trim() || undefined;

  const databasePath = env.DATABASE_PATH?.trim() || DEFAULT_DB_PATH;

  return {
    nodeEnv,
    isProduction,
    host: env.HOST?.trim() || DEFAULT_HOST,
    port: parsePort(env.PORT),
    databasePath,
    sessionSecret,
    // Безопасный дефолт (NFR-10): в проде cookie только по HTTPS, в dev/test — по HTTP.
    cookieSecure: parseBool(env.COOKIE_SECURE, isProduction),
    corsOrigin: env.CORS_ORIGIN?.trim() || DEFAULT_CORS_ORIGIN,
    logLevel: env.LOG_LEVEL?.trim() || DEFAULT_LOG_LEVEL,
    staticDir: env.STATIC_DIR?.trim() || DEFAULT_STATIC_DIR,
  };
}
