/**
 * api/notes.ts — заметки и теги (PLAN §3.2).
 *
 * Тонкие обёртки над `apiRequest` из `client.ts`: CSRF-заголовок и обработка
 * 401 берутся оттуда (state-changing `DELETE` автоматически получает
 * `X-CSRF-Token`). Поиск/фильтр — серверные (`?q=&tag=`), комбинируются по «И».
 */
import { apiRequest } from './client';

/** Заметка в контракте сервера (PLAN §3.2). `title` может отсутствовать. */
export interface Note {
  id: number;
  title: string | null;
  bodyMarkdown: string;
  tags: string[];
  createdAt: string;
  updatedAt: string;
}

export interface NotesQuery {
  /** Подстрочный поиск по заголовку и телу (пустое — без фильтра). */
  q?: string;
  /** Фильтр по имени тега (пустое/`null` — без фильтра). */
  tag?: string | null;
}

export interface NotesListResponse {
  items: Note[];
  total: number;
}

/** Тело создания/обновления заметки (PLAN §3.2). */
export interface NoteInput {
  title: string | null;
  bodyMarkdown: string;
  tags: string[];
}

/** Тег пользователя со счётчиком заметок (GET /api/tags). */
export interface TagCount {
  name: string;
  count: number;
}

export const notesApi = {
  /** `GET /api/notes?q=&tag=` — свои заметки, сортировка `updatedAt DESC`. */
  list: (query: NotesQuery = {}): Promise<NotesListResponse> => {
    const params = new URLSearchParams();
    const q = query.q?.trim();
    const tag = query.tag?.trim();
    if (q) params.set('q', q);
    if (tag) params.set('tag', tag);
    const qs = params.toString();
    return apiRequest<NotesListResponse>(`/api/notes${qs ? `?${qs}` : ''}`);
  },

  /** `DELETE /api/notes/:id` → 204 (204 → `undefined`). */
  remove: (id: number): Promise<void> =>
    apiRequest<void>(`/api/notes/${id}`, { method: 'DELETE' }),

  /** `GET /api/notes/:id` → `Note` (чужой/несуществующий → `404`). */
  get: (id: number): Promise<Note> => apiRequest<Note>(`/api/notes/${id}`),

  /** `POST /api/notes` → `201 Note` (пустая заметка → `422`). */
  create: (input: NoteInput): Promise<Note> =>
    apiRequest<Note>('/api/notes', { method: 'POST', body: input }),

  /** `PATCH /api/notes/:id` (частично) → `200 Note`. */
  update: (id: number, input: NoteInput): Promise<Note> =>
    apiRequest<Note>(`/api/notes/${id}`, { method: 'PATCH', body: input }),
};

export const tagsApi = {
  /** `GET /api/tags` — теги пользователя со счётчиками (для чипов-фильтров). */
  list: (): Promise<{ items: TagCount[] }> =>
    apiRequest<{ items: TagCount[] }>('/api/tags'),
};
