/**
 * config.ts — конфигурация сервера из переменных окружения (PLAN §2, §4.7).
 *
 * Правила:
 *   * секреты приходят только из env (NFR-8) — в коде нет значений по умолчанию для `SESSION_SECRET`;
 *   * в dev/test при отсутствии секрета генерируется эфемерный (сервер поднимается без настройки),
 *     в проде отсутствие секрета — фатальная ошибка;
 *   * все значения типизированы и валидируются на границе (порт, булевы флаги).
 */
import { randomBytes } from 'node:crypto';
import { DEFAULT_DB_PATH } from './db/client.js';

export type NodeEnv = 'development' | 'production' | 'test';

export interface Config {
  nodeEnv: NodeEnv;
  isProduction: boolean;
  /** Адрес прослушивания. По умолчанию только localhost (dev). */
  host: string;
  port: number;
  databasePath: string;
  sessionSecret: string;
  cookieSecure: boolean;
  corsOrigin: string;
  logLevel: string;
}

export const DEFAULT_PORT = 3000;
export const DEFAULT_HOST = '127.0.0.1';
/** Dev-ориджин Vite (PLAN §2: фронтенд-dev 5173). */
export const DEFAULT_CORS_ORIGIN = 'http://localhost:5173';
export const DEFAULT_LOG_LEVEL = 'info';

/** Ошибка конфигурации: секрет обязателен и не задан (NFR-8). */
export class MissingSecretError extends Error {
  constructor(name: string) {
    super(`Переменная окружения ${name} обязательна в production (NFR-8)`);
    this.name = 'MissingSecretError';
  }
}

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

  const providedSecret = env.SESSION_SECRET?.trim();
  let sessionSecret: string;
  if (providedSecret) {
    sessionSecret = providedSecret;
  } else if (isProduction) {
    throw new MissingSecretError('SESSION_SECRET');
  } else {
    // Dev/test: эфемерный секрет — сервер поднимается без .env; при перезапуске сессии инвалидируются.
    sessionSecret = randomBytes(32).toString('base64url');
  }

  const databasePath = env.DATABASE_PATH?.trim() || DEFAULT_DB_PATH;

  return {
    nodeEnv,
    isProduction,
    host: env.HOST?.trim() || DEFAULT_HOST,
    port: parsePort(env.PORT),
    databasePath,
    sessionSecret,
    cookieSecure: parseBool(env.COOKIE_SECURE, isProduction),
    corsOrigin: env.CORS_ORIGIN?.trim() || DEFAULT_CORS_ORIGIN,
    logLevel: env.LOG_LEVEL?.trim() || DEFAULT_LOG_LEVEL,
  };
}
