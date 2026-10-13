/**
 * lib/notes.ts — доменные правила заметок (PLAN §3.2/§3.3, T-04).
 *
 * Здесь только то, что не зависит от HTTP: валидация входа, приведение строк БД к
 * контракту `Note = {id, title, bodyMarkdown, tags, createdAt, updatedAt}` и нормализация
 * тегов. Ownership-фильтрация (`WHERE user_id = ?`) — в `routes/notes.ts` (PLAN §4.4).
 *
 * Инварианты:
 *   * `title` — опциональное поле: пустая/пробельная строка трактуется как «заголовка нет» (`null`);
 *   * `body_markdown` в БД `NOT NULL` — отсутствие текста хранится как `''`;
 *   * заметка «пустая» (нет заголовка И нет непустого текста) не сохраняется (AC-17/E1).
 */
import { AppError } from './errors.js';

/** Границы валидации (PLAN §3.2/NFR-7). */
export const MAX_TITLE_LENGTH = 200;
export const MAX_BODY_LENGTH = 100_000;

/** Единое сообщение для «пустой заметки» (AC-17/E1). */
export const EMPTY_NOTE_MESSAGE = 'Заметка не может быть пустой — добавьте заголовок или текст';
/** Единое сообщение 404 для чужой/несуществующей заметки (Q-A7: без раскрытия существования). */
export const NOTE_NOT_FOUND_MESSAGE = 'Заметка не найдена';
/** PATCH без распознанных полей — явная ошибка вместо молчаливого no-op. */
export const NO_UPDATE_FIELDS_MESSAGE = 'Укажите хотя бы одно поле для обновления';

/** Публичное представление заметки (контракт API, PLAN §3.2). */
export interface Note {
  id: number;
  title: string | null;
  bodyMarkdown: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

/** Строка таблицы `notes` как её возвращают statements из `db/client.ts`. */
export interface NoteRow {
  id: number;
  user_id: number;
  title: string | null;
  body_markdown: string;
  created_at: string;
  updated_at: string;
}

/** Валидированные данные создания заметки. */
export interface NoteInput {
  title: string | null;
  bodyMarkdown: string;
  tags: string[];
}

/** Частичное обновление: присутствуют только переданные ключи. */
export interface NotePatch {
  title?: string | null;
  bodyMarkdown?: string;
  tags?: string[];
}

/** Единая ошибка «заметка не найдена» (не отличает чужую от несуществующей, Q-A7/AC-11). */
export function noteNotFound(): AppError {
  return new AppError(404, 'NOT_FOUND', NOTE_NOT_FOUND_MESSAGE);
}

function fieldError(message: string, field: string): AppError {
  return new AppError(422, 'VALIDATION_ERROR', message, { field });
}

/** Строка БД → контракт API. */
export function toNote(row: NoteRow, tags: string[]): Note {
  return {
    id: row.id,
    title: row.title,
    bodyMarkdown: row.body_markdown,
    tags: [...tags],
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/** Заголовок: `undefined`/`null`/пробельная строка → `null`; проверяет тип и длину. */
function parseTitle(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') {
    throw fieldError('Заголовок должен быть строкой', 'title');
  }
  if (value.length > MAX_TITLE_LENGTH) {
    throw fieldError(`Заголовок не должен превышать ${MAX_TITLE_LENGTH} символов`, 'title');
  }
  return value.trim() === '' ? null : value;
}

/** Тело заметки: отсутствие допускается (заметка «только заголовок», E2); проверяет тип и длину. */
function parseBody(value: unknown): string {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') {
    throw fieldError('Текст заметки должен быть строкой', 'bodyMarkdown');
  }
  if (value.length > MAX_BODY_LENGTH) {
    throw fieldError(`Текст заметки не должен превышать ${MAX_BODY_LENGTH} символов`, 'bodyMarkdown');
  }
  return value;
}

/**
 * Нормализует список тегов: тримминг, отбрасывание пустых, дедупликация без учёта регистра
 * с сохранением первого написания (Q-T2). Лимиты количества/длины — зона T-05.
 */
export function parseTags(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw fieldError('Теги должны быть массивом строк', 'tags');
  }
  const names: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== 'string') {
      throw fieldError('Теги должны быть массивом строк', 'tags');
    }
    const name = item.trim();
    if (name === '') continue;
    const norm = name.toLowerCase();
    if (seen.has(norm)) continue;
    seen.add(norm);
    names.push(name);
  }
  return names;
}

/** Правило «заметка не пустая»: нужен заголовок или непустой текст (AC-17/E1). */
export function assertNoteNotEmpty(title: string | null, bodyMarkdown: string): void {
  if (title === null && bodyMarkdown.trim() === '') {
    throw new AppError(422, 'VALIDATION_ERROR', EMPTY_NOTE_MESSAGE);
  }
}

/** Валидирует тело POST /api/notes. @throws AppError 422 */
export function parseNoteInput(body: unknown): NoteInput {
  const record = (body ?? {}) as Record<string, unknown>;
  const title = parseTitle(record.title);
  const bodyMarkdown = parseBody(record.bodyMarkdown);
  assertNoteNotEmpty(title, bodyMarkdown);
  return {
    title,
    bodyMarkdown,
    tags: record.tags === undefined ? [] : parseTags(record.tags),
  };
}

/**
 * Валидирует тело PATCH /api/notes/:id: возвращает только переданные поля.
 * Пустой объект — ошибка (нет полей для обновления). @throws AppError 422
 */
export function parseNotePatch(body: unknown): NotePatch {
  const record = (body ?? {}) as Record<string, unknown>;
  const patch: NotePatch = {};
  if ('title' in record) patch.title = parseTitle(record.title);
  if ('bodyMarkdown' in record) patch.bodyMarkdown = parseBody(record.bodyMarkdown);
  if ('tags' in record) patch.tags = parseTags(record.tags);
  if (Object.keys(patch).length === 0) {
    throw new AppError(422, 'VALIDATION_ERROR', NO_UPDATE_FIELDS_MESSAGE);
  }
  return patch;
}
