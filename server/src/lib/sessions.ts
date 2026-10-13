/**
 * lib/sessions.ts — cookie-сессии и CSRF-токен (PLAN §4.2, §4.3).
 *
 * Модель:
 *   * cookie `session` хранит opaque token `crypto.randomBytes(32).base64url`; в БД — только SHA-256;
 *   * cookie `XSRF-TOKEN` дублирует `csrf_token` сессии для double-submit (читаемый, без HttpOnly);
 *   * срок 7 суток со скользящим продлением (`touch` при каждом использовании).
 *
 * Здесь же — минимальные утилиты cookie (разбор/сериализация), чтобы не тянуть лишнюю зависимость.
 */
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { runInsert, type Statements } from '../db/client.js';

export const SESSION_COOKIE = 'session';
export const CSRF_COOKIE = 'XSRF-TOKEN';
export const CSRF_HEADER = 'x-csrf-token';
export const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const SESSION_MAX_AGE_SECONDS = Math.floor(SESSION_TTL_MS / 1000);

export interface SessionRecord {
  id: number;
  token_hash: string;
  user_id: number;
  csrf_token: string;
  created_at: string;
  expires_at: string;
}

export interface IssuedSession {
  /** Raw token — только для cookie, в БД не хранится. */
  token: string;
  /** CSRF-токен: дублируется в cookie и в сессии. */
  csrfToken: string;
  expiresAt: string;
}

/** Генерирует 256-битный opaque токен в base64url. */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

/** SHA-256 токена (hex) — то, что хранится в БД. */
export function hashToken(rawToken: string): string {
  return createHash('sha256').update(rawToken).digest('hex');
}

/** Сравнение секретов постоянного времени (защита от timing-атак на CSRF-токен). */
export function tokensMatch(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

/** ISO-строка в прошлом? (строки одного формата сравниваются лексикографически). */
export function isExpired(session: SessionRecord, nowIso: string): boolean {
  return session.expires_at <= nowIso;
}

/** Создаёт запись сессии и возвращает выпущенные токены (raw не пишется в БД). */
export function createSession(
  stmts: Statements,
  userId: number,
  now: Date = new Date(),
): IssuedSession {
  const token = generateToken();
  const csrfToken = generateToken();
  const createdAt = now.toISOString();
  const expiresAt = new Date(now.getTime() + SESSION_TTL_MS).toISOString();
  runInsert(stmts.insertSession, hashToken(token), userId, csrfToken, createdAt, expiresAt);
  return { token, csrfToken, expiresAt };
}

/** Находит сессию по raw-токену cookie (без проверки срока). */
export function findSession(stmts: Statements, rawToken: string): SessionRecord | null {
  const row = stmts.getSessionByTokenHash.get(hashToken(rawToken)) as SessionRecord | undefined;
  return row ?? null;
}

/** Скользящее продление: сдвигает `expires_at` на +7 суток от текущего момента. */
export function touchSession(stmts: Statements, sessionId: number, now: Date = new Date()): void {
  stmts.touchSession.run(new Date(now.getTime() + SESSION_TTL_MS).toISOString(), sessionId);
}

/** Инвалидирует сессию по raw-токену (logout). Возвращает true, если что-то удалено. */
export function deleteSessionByToken(stmts: Statements, rawToken: string): boolean {
  const result = stmts.deleteSessionByTokenHash.run(hashToken(rawToken));
  return Number(result.changes) > 0;
}

/** Удаляет просроченные сессии (уборка при разборе cookie). */
export function purgeExpiredSessions(stmts: Statements, nowIso: string): void {
  stmts.deleteExpiredSessions.run(nowIso);
}

// ---------------------------------------------------------------------------
// Cookie: разбор заголовка и сериализация (минимальная реализация по RFC 6265).
// ---------------------------------------------------------------------------

export interface CookieOptions {
  maxAge?: number;
  httpOnly?: boolean;
  secure?: boolean;
  sameSite?: 'Lax' | 'Strict' | 'None';
  path?: string;
}

/** Разбирает заголовок `Cookie` в словарь (последнее значение побеждает). */
export function parseCookies(header: string | undefined): Record<string, string> {
  const result: Record<string, string> = {};
  if (!header) return result;
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const name = part.slice(0, eq).trim();
    if (name === '') continue;
    const value = part.slice(eq + 1).trim();
    try {
      result[name] = decodeURIComponent(value);
    } catch {
      result[name] = value;
    }
  }
  return result;
}

/** Сериализует один Set-Cookie (атрибуты — только заданные). */
export function serializeCookie(name: string, value: string, options: CookieOptions = {}): string {
  const parts = [`${name}=${encodeURIComponent(value)}`];
  parts.push(`Path=${options.path ?? '/'}`);
  if (options.maxAge !== undefined) parts.push(`Max-Age=${options.maxAge}`);
  if (options.httpOnly) parts.push('HttpOnly');
  if (options.secure) parts.push('Secure');
  parts.push(`SameSite=${options.sameSite ?? 'Lax'}`);
  return parts.join('; ');
}
