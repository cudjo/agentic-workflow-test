/**
 * lib/search.ts — серверный поиск и фильтр заметок (PLAN §3.2, T-05).
 *
 * Поиск подстрочный, регистронезависимый, по `title` + `body_markdown` (исходный markdown,
 * Q-S1/Q-S2). Спецсимволы LIKE (`%`, `_`, `\`) трактуются как литералы (S1) — они
 * экранируются, а в SQL используется `... LIKE ? ESCAPE '\'`.
 *
 * Регистронезависимость и кириллица:
 *   SQLite встроенные `LOWER()` и `COLLATE NOCASE` работают только с ASCII (проверено:
 *   `lower('Привет') LIKE lower('%ПРИВЕТ%')` не находит). Поэтому регистр приводит
 *   SQL-функция `search_norm`, зарегистрированная из JS (`String.prototype.toLowerCase`,
 *   Unicode-aware) — тот же подход, что и для `tags.name_norm`/`users.email_norm` в T-04.
 *   Это позволяет находить заметки независимо от регистра как латиницы, так и кириллицы.
 */
import type { DatabaseSync } from 'node:sqlite';

/** Имя SQL-функции нормализации регистра (регистрируется в `db/client.ts`). */
export const SEARCH_NORM_FUNCTION = 'search_norm';

/** Символ экранирования для `LIKE ... ESCAPE`. */
export const LIKE_ESCAPE = '\\';

/** Регистронезависимая Unicode-нормализация строки (кириллица в т.ч.). */
export function normalizeForSearch(value: string): string {
  return value.toLowerCase();
}

/** Экранирует спецсимволы LIKE (`\`, `%`, `_`) → они становятся литералами (S1). */
export function escapeLikePattern(value: string): string {
  return value.replace(/[\\%_]/g, (char) => LIKE_ESCAPE + char);
}

/** LIKE-паттерн подстрочного поиска `%…%` (спецсимволы — литералы, регистр — Unicode). */
export function toLikePattern(query: string): string {
  return `%${escapeLikePattern(normalizeForSearch(query))}%`;
}

/**
 * Регистрирует JS-функцию `search_norm` на соединении (замена ASCII-only `LOWER()`).
 * Идемпотентно: повторная регистрация переопределяет функцию без ошибки.
 */
export function registerSearchFunctions(db: DatabaseSync): void {
  db.function(
    SEARCH_NORM_FUNCTION,
    { deterministic: true },
    (value: unknown) => (value === null || value === undefined ? '' : String(value).toLowerCase()),
  );
}

/** Разобранный фильтр списка заметок: параметры готовы к биндингу в SQL. */
export interface NotesFilter {
  /** LIKE-паттерн поиска по title+body или `null` (нет поиска) — S4. */
  qPattern: string | null;
  /** Нормализованное имя тега или `null` (нет фильтра). */
  tagNorm: string | null;
}

/** Значение query-параметра: строка (первая, если массив) либо `undefined`. */
function firstString(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
  return undefined;
}

/**
 * Разбирает `?q=&tag=`: пустые значения → отсутствие фильтра (S4);
 * `tag` нормализуется как `tags.name_norm` (Unicode-регистр).
 */
export function parseNotesFilter(query: unknown): NotesFilter {
  const record = (query ?? {}) as Record<string, unknown>;
  const rawQ = firstString(record.q);
  const rawTag = firstString(record.tag)?.trim();
  return {
    qPattern: rawQ === undefined || rawQ === '' ? null : toLikePattern(rawQ),
    tagNorm: rawTag === undefined || rawTag === '' ? null : normalizeForSearch(rawTag),
  };
}
