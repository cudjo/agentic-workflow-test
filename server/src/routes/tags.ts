/**
 * routes/tags.ts — теги пользователя (PLAN §3.2, T-05).
 *
 * `GET /api/tags` → `{items: [{name, count}]}` — теги текущего пользователя со счётчиком
 * заметок (для чипов-фильтров и `datalist`, T-08/T-09). Отдаются только свои теги
 * (приватность, Q-T4/AC-44): выборка фильтруется `WHERE t.user_id = ?`; теги без заметок
 * не возвращаются (`HAVING COUNT > 0`) и физически чистятся при удалении/смене тегов (T6).
 */
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../middleware/auth.js';

interface TagCountRow {
  name: string;
  count: number | bigint;
}

export async function tagsRoutes(app: FastifyInstance): Promise<void> {
  app.get('/api/tags', { preHandler: requireAuth }, async (request) => {
    const userId = request.user!.id;
    const rows = app.stmts.listTagsByUser.all(userId) as unknown as TagCountRow[];
    const items = rows.map((row) => ({ name: row.name, count: Number(row.count) }));
    return { items };
  });
}
