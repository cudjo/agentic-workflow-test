/**
 * index.ts — entrypoint сервера (PLAN §2): config → app → listen.
 *
 * Запуск: `npm run dev` (tsx watch) или `npm start`.
 */
import { buildApp } from './app.js';
import { loadConfig } from './config.js';

async function main(): Promise<void> {
  const config = loadConfig();
  const app = await buildApp({ config });

  const shutdown = async (signal: string): Promise<void> => {
    app.log.info({ signal }, 'остановка сервера');
    await app.close();
    process.exit(0);
  };
  process.once('SIGINT', () => void shutdown('SIGINT'));
  process.once('SIGTERM', () => void shutdown('SIGTERM'));

  try {
    await app.listen({ host: config.host, port: config.port });
  } catch (error) {
    app.log.error({ err: error }, 'не удалось запустить сервер');
    process.exit(1);
  }
}

void main();
