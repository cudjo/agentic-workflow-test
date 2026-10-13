/**
 * middleware/rateLimit.ts — in-memory лимитер попыток входа/регистрации (PLAN §4.6, NFR-12).
 *
 * Ключ — `ip + email` (нормализованный). Считаются только неудачные попытки:
 *   * логин — неверные учётные данные (401);
 *   * регистрация — занятый email (409).
 * Валидационные ошибки (422) не считаются, чтобы не блокировать пользователя за опечатки.
 *
 * По достижении лимита — 429 + заголовок `Retry-After` (секунды).
 * Реализация осознанно in-memory и однопроцессная (PLAN R4; T-12 документирует ограничение).
 */
import type { FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from '../lib/errors.js';

/** 5 неудач за 15 минут (PLAN §4.6). */
export const DEFAULT_MAX_ATTEMPTS = 5;
export const DEFAULT_WINDOW_MS = 15 * 60 * 1000;

export interface RateLimitStatus {
  allowed: boolean;
  /** Секунды до сброса окна (для заголовка Retry-After); 0, если запрос разрешён. */
  retryAfter: number;
  remaining: number;
}

interface Entry {
  count: number;
  resetAt: number;
}

export interface RateLimiter {
  /** Проверяет, не превышен ли лимит для ключа (не увеличивает счётчик). */
  check(key: string): RateLimitStatus;
  /** Регистрирует неудачную попытку. */
  fail(key: string): void;
  /** Сбрасывает счётчик (например, после успешного входа). */
  reset(key: string): void;
  /** Полная очистка (тесты). */
  clear(): void;
}

export interface RateLimiterOptions {
  max?: number;
  windowMs?: number;
  /** Инъекция часов для детерминированных тестов. */
  now?: () => number;
}

export function createRateLimiter(options: RateLimiterOptions = {}): RateLimiter {
  const max = options.max ?? DEFAULT_MAX_ATTEMPTS;
  const windowMs = options.windowMs ?? DEFAULT_WINDOW_MS;
  const now = options.now ?? (() => Date.now());
  const entries = new Map<string, Entry>();

  function activeEntry(key: string, at: number): Entry | undefined {
    const entry = entries.get(key);
    if (entry && entry.resetAt <= at) {
      entries.delete(key);
      return undefined;
    }
    return entry;
  }

  return {
    check(key) {
      const at = now();
      const entry = activeEntry(key, at);
      if (!entry || entry.count < max) {
        return { allowed: true, retryAfter: 0, remaining: entry ? max - entry.count : max };
      }
      const retryAfter = Math.max(1, Math.ceil((entry.resetAt - at) / 1000));
      return { allowed: false, retryAfter, remaining: 0 };
    },
    fail(key) {
      const at = now();
      let entry = activeEntry(key, at);
      if (!entry) {
        entry = { count: 0, resetAt: at + windowMs };
        entries.set(key, entry);
      }
      entry.count += 1;
    },
    reset(key) {
      entries.delete(key);
    },
    clear() {
      entries.clear();
    },
  };
}

/** Ключ лимита: ip + нормализованный email из тела запроса. */
export function loginRateLimitKey(request: FastifyRequest): string {
  const body = (request.body ?? {}) as { email?: unknown };
  const email =
    typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  return `${request.ip}:${email}`;
}

/** Применяет заголовок Retry-After и бросает 429 (единый формат ошибки, PLAN §3.2). */
export function tooManyRequests(reply: FastifyReply, retryAfter: number): never {
  reply.header('Retry-After', String(retryAfter));
  throw new AppError(
    429,
    'RATE_LIMITED',
    `Слишком много попыток. Повторите через ${retryAfter} с`,
  );
}
