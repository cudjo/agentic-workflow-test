/**
 * routes/health.ts — health-check (PLAN §3.2, T-02).
 * Без авторизации: используется внешними проверками (init, T-12 healthcheck).
 */
import type { FastifyInstance } from 'fastify';

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  app.get('/health', async () => ({ ok: true }));
}
