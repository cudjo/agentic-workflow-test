/**
 * api/client.ts — тонкая обёртка над `fetch` (PLAN §3.3).
 *
 *   * `credentials: 'include'` — сессия в HttpOnly-cookie;
 *   * state-changing (`POST`/`PATCH`/`PUT`/`DELETE`) добавляют заголовок
 *     `X-CSRF-Token` из читаемой cookie `XSRF-TOKEN` (double-submit, NFR-11);
 *   * `401` вне auth-эндпоинтов → колбэк `notifyUnauthorized()`: приложение
 *     сбрасывает состояние и редиректит на `/login` с сохранением целевого URL
 *     (DESIGN §1.2 поток B; AC-9/AC-10).
 *
 * Ошибки приводятся к единому контракту сервера `{error:{code,message,field?}}`
 * (PLAN §3.2) и выбрасываются как `ApiError`.
 */

export interface ApiErrorBody {
  code: string;
  message: string;
  field?: string;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly field?: string;
  /** Секунды из заголовка `Retry-After` (для баннера rate-limit, 429). */
  readonly retryAfter?: number;

  constructor(status: number, body: Partial<ApiErrorBody>, retryAfter?: number) {
    super(body.message ?? 'Ошибка запроса');
    this.name = 'ApiError';
    this.status = status;
    this.code = body.code ?? 'ERROR';
    this.field = body.field;
    this.retryAfter = retryAfter;
  }
}

let unauthorizedHandler: (() => void) | null = null;

/** Регистрирует обработчик неавторизованного доступа (вызывает AuthProvider). */
export function setUnauthorizedHandler(handler: (() => void) | null): void {
  unauthorizedHandler = handler;
}

/** Вызывает зарегистрированный обработчик 401 (если есть). */
export function notifyUnauthorized(): void {
  unauthorizedHandler?.();
}

const STATE_CHANGING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);
const CSRF_COOKIE = 'XSRF-TOKEN';
const CSRF_HEADER = 'X-CSRF-Token';
const RETRY_AFTER = 'Retry-After';

/** Читает значение cookie по имени (undefined-safe в SSR/тестах). */
export function getCookie(name: string): string | null {
  if (typeof document === 'undefined') return null;
  const prefix = `${name}=`;
  for (const part of document.cookie.split(';')) {
    const trimmed = part.trim();
    if (trimmed.startsWith(prefix)) {
      return decodeURIComponent(trimmed.slice(prefix.length));
    }
  }
  return null;
}

export interface RequestOptions {
  method?: string;
  body?: unknown;
  /** `true` — не триггерить глобальный редирект на 401 (использует `me`). */
  skipAuthRedirect?: boolean;
}

/** Базовый запрос к API. Возвращает распарсенный JSON либо `undefined` для 204. */
export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const method = (options.method ?? 'GET').toUpperCase();
  const headers: Record<string, string> = { Accept: 'application/json' };
  const init: RequestInit = { method, credentials: 'include', headers };

  if (options.body !== undefined) {
    headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(options.body);
  }

  if (STATE_CHANGING_METHODS.has(method)) {
    const token = getCookie(CSRF_COOKIE);
    if (token) headers[CSRF_HEADER] = token;
  }

  const response = await fetch(path, init);

  if (response.status === 401 && !options.skipAuthRedirect) {
    notifyUnauthorized();
  }

  if (response.status === 204) {
    return undefined as T;
  }

  const raw = await response.text();
  let payload: unknown = null;
  if (raw) {
    try {
      payload = JSON.parse(raw);
    } catch {
      payload = null;
    }
  }

  if (!response.ok) {
    const error = (payload as { error?: ApiErrorBody } | null)?.error ?? {};
    const retryHeader = response.headers?.get?.(RETRY_AFTER) ?? null;
    const parsedRetry = retryHeader ? Number.parseInt(retryHeader, 10) : Number.NaN;
    throw new ApiError(
      response.status,
      error,
      Number.isFinite(parsedRetry) ? parsedRetry : undefined,
    );
  }

  return payload as T;
}

export interface User {
  id: number;
  email: string;
}

/** Auth-эндпоинты (PLAN §3.2). */
export const authApi = {
  /** Восстановление сессии; 401 ожидаем и не должен вызывать редирект-эффект. */
  me: (): Promise<{ user: User }> =>
    apiRequest<{ user: User }>('/api/auth/me', { skipAuthRedirect: true }),

  login: (email: string, password: string): Promise<{ user: User }> =>
    apiRequest<{ user: User }>('/api/auth/login', {
      method: 'POST',
      body: { email, password },
    }),

  register: (email: string, password: string): Promise<{ user: User }> =>
    apiRequest<{ user: User }>('/api/auth/register', {
      method: 'POST',
      body: { email, password },
    }),

  logout: (): Promise<void> =>
    apiRequest<void>('/api/auth/logout', { method: 'POST' }),
};
