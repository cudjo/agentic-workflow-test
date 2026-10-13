/**
 * routes/notes.ts — CRUD заметок с ownership-проверкой (PLAN §3.2, §4.4; T-04).
 *
 * Гарантии:
 *   * каждая операция выполняется от лица `request.user` (middleware `requireAuth`), и все
 *     запросы к `notes` фильтруются `WHERE user_id = :uid` — чужой/несуществующий id → 404
 *     без раскрытия существования ресурса (AC-11…AC-14, Q-A7);
 *   * запись (создание/обновление/удаление + связи тегов) — в одной транзакции (NFR-26);
 *   * порядок списка — `updated_at DESC` (Q-S3), контракт ответа — `{items, total}`;
 *   * `Note = {id, title, bodyMarkdown, tags, createdAt, updatedAt}` (PLAN §3.2).
 *
 * Поиск/фильтр (T-05): `GET /api/notes?q=&tag=` — подстрочный регистронезависимый поиск по
 * `title` + `body_markdown` (спецсимволы LIKE — литералы), фильтр по тегу, комбинация по «И»
 * (AC-40/AC-41), всегда в пределах владельца (AC-44/S7). Детали — `lib/search.ts`.
 *
 * Теги (T-05): лимиты (≤20/≤50) в `parseTags()`, `GET /api/tags` — в `routes/tags.ts`,
 * чистка осиротевших тегов — `deleteOrphanTagsForUser` после операций, меняющих набор тегов.
 */
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { nowIso, runInsert, transaction } from '../db/client.js';
import {
  assertNoteNotEmpty,
  noteNotFound,
  parseNoteInput,
  parseNotePatch,
  toNote,
  type Note,
  type NoteRow,
} from '../lib/notes.js';
import { parseNotesFilter } from '../lib/search.js';
import { requireAuth } from '../middleware/auth.js';

interface TagRow {
  id: number;
  name: string;
}

interface IdParams {
  id: string;
}

/** Идентификатор владельца: `requireAuth` уже гарантировал `request.user`. */
function ownerId(request: FastifyRequest): number {
  // Гарантирован preHandler'ом requireAuth на всех роутах файла.
  return request.user!.id;
}

/** Разбирает `:id`: нечисловой/неположительный id — такой же 404, как чужой (Q-A7). */
function parseNoteId(raw: string): number {
  const id = Number(raw);
  if (!/^[0-9]+$/.test(raw) || !Number.isSafeInteger(id) || id <= 0) {
    throw noteNotFound();
  }
  return id;
}

/** Заметка пользователя или 404 (чужой и несуществующий id неразличимы). */
function noteOr404(app: FastifyInstance, noteId: number, userId: number): NoteRow {
  const row = app.stmts.getNoteById.get(noteId, userId) as NoteRow | undefined;
  if (!row) throw noteNotFound();
  return row;
}

/** Теги заметки в исходном написании, отсортированы по имени (PLAN §3.2). */
function noteTags(app: FastifyInstance, noteId: number): string[] {
  return (app.stmts.getTagsForNote.all(noteId) as unknown as TagRow[]).map((row) => row.name);
}

/**
 * Заменяет набор тегов заметки: отвязывает прежние и привязывает новые, переиспользуя
 * существующие теги пользователя по `name_norm` (регистронезависимо, Q-T2).
 * Вызывать только внутри транзакции.
 */
function replaceNoteTags(
  app: FastifyInstance,
  userId: number,
  noteId: number,
  names: string[],
): void {
  app.stmts.unlinkNoteTagsByNote.run(noteId);
  for (const name of names) {
    const norm = name.toLowerCase();
    const existing = app.stmts.getTagByUserAndNorm.get(userId, norm) as TagRow | undefined;
    const tagId = existing ? existing.id : runInsert(app.stmts.insertTag, userId, name, norm);
    app.stmts.linkNoteTag.run(noteId, tagId);
  }
  // Теги, потерявшие последнюю заметку, удаляем — «нет битых ссылок и пустых тегов» (T6).
  app.stmts.deleteOrphanTagsForUser.run(userId);
}

export async function notesRoutes(app: FastifyInstance): Promise<void> {
  const auth = { preHandler: requireAuth };

  // GET /api/notes — только свои заметки, свежие сверху (AC-13, Q-S3); поиск `q` + фильтр `tag` (T-05).
  app.get('/api/notes', auth, async (request) => {
    const userId = ownerId(request);
    const { qPattern, tagNorm } = parseNotesFilter(request.query);
    const rows = app.stmts.listNotesFiltered.all(
      userId,
      qPattern,
      qPattern,
      qPattern,
      tagNorm,
      tagNorm,
    ) as unknown as NoteRow[];
    const items: Note[] = rows.map((row) => toNote(row, noteTags(app, row.id)));
    return { items, total: items.length };
  });

  // POST /api/notes — создание (201 Note).
  app.post('/api/notes', auth, async (request, reply) => {
    const userId = ownerId(request);
    const input = parseNoteInput(request.body);
    const now = nowIso();

    const note = transaction(app.db, () => {
      const id = runInsert(app.stmts.insertNote, userId, input.title, input.bodyMarkdown, now, now);
      if (input.tags.length > 0) replaceNoteTags(app, userId, id, input.tags);
      const row: NoteRow = {
        id,
        user_id: userId,
        title: input.title,
        body_markdown: input.bodyMarkdown,
        created_at: now,
        updated_at: now,
      };
      return toNote(row, noteTags(app, id));
    });

    return reply.code(201).send(note);
  });

  // GET /api/notes/:id — своя заметка или 404 (AC-11/AC-14).
  app.get('/api/notes/:id', auth, async (request) => {
    const params = request.params as IdParams;
    const row = noteOr404(app, parseNoteId(params.id), ownerId(request));
    return toNote(row, noteTags(app, row.id));
  });

  // PATCH /api/notes/:id — частичное обновление (200 Note).
  app.patch('/api/notes/:id', auth, async (request) => {
    const userId = ownerId(request);
    const noteId = parseNoteId((request.params as IdParams).id);
    const patch = parseNotePatch(request.body);
    const row = noteOr404(app, noteId, userId);

    const title = 'title' in patch ? patch.title! : row.title;
    const bodyMarkdown = 'bodyMarkdown' in patch ? patch.bodyMarkdown! : row.body_markdown;
    assertNoteNotEmpty(title, bodyMarkdown);

    const now = nowIso();
    transaction(app.db, () => {
      app.stmts.updateNote.run(title, bodyMarkdown, now, noteId, userId);
      if ('tags' in patch) replaceNoteTags(app, userId, noteId, patch.tags!);
    });

    const updated: NoteRow = {
      ...row,
      title,
      body_markdown: bodyMarkdown,
      updated_at: now,
    };
    return toNote(updated, noteTags(app, noteId));
  });

  // DELETE /api/notes/:id — 204; связи note_tags удаляются каскадом (FK ON DELETE CASCADE).
  app.delete('/api/notes/:id', auth, async (request, reply) => {
    const userId = ownerId(request);
    const noteId = parseNoteId((request.params as IdParams).id);

    transaction(app.db, () => {
      const result = app.stmts.deleteNote.run(noteId, userId);
      if (Number(result.changes) === 0) throw noteNotFound();
      // FK-каскад убрал note_tags; подчищаем теги, оставшиеся без заметок (T6).
      app.stmts.deleteOrphanTagsForUser.run(userId);
    });

    return reply.code(204).send();
  });
}
