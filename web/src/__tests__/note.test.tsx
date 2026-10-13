/**
 * note.test.tsx — сценарии T-10: экран просмотра заметки (S5, `/notes/:id`).
 *
 * Покрытие приёмки: открытие показывает отрендеренный markdown и сохранённое
 * содержимое; чужой/несуществующий id → «Заметка не найдена» (404, без раскрытия);
 * теги и заголовок рендерятся как текст (HTML-подобные символы не исполняются,
 * AC-47/NFR-14); удаление из просмотра → подтверждение → возврат к списку;
 * один h1 на странице, заголовки markdown начинаются с h2 (DESIGN §5.4).
 *
 * `fetch` мокается целиком, ответы строятся как на сервере (PLAN §3.2).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import App from '../App';
import { AuthProvider } from '../auth/AuthContext';
import type { Note } from '../api/notes';

/* ------------------------------- окружение -------------------------------- */

function json(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: () => null },
    text: async () => JSON.stringify(body),
  } as unknown as Response;
}

function noContent(status = 204): Response {
  return {
    ok: true,
    status,
    headers: { get: () => null },
    text: async () => '',
  } as unknown as Response;
}

type FetchHandler = (url: string, init: RequestInit) => Response | Promise<Response>;

let fetchMock: ReturnType<typeof vi.fn>;

function setupFetch(handler: FetchHandler): void {
  fetchMock = vi.fn(async (input: unknown, init?: RequestInit) => {
    const url =
      typeof input === 'string' ? input : String((input as { url?: string })?.url ?? input);
    return handler(url, init ?? {});
  });
  vi.stubGlobal('fetch', fetchMock);
}

/** Дата без таймзоны → локальное время: формат детерминирован в любом TZ. */
const localIso = (year: number, monthIndex: number, day: number, hours: number, minutes: number) =>
  new Date(year, monthIndex, day, hours, minutes).toISOString();

const NOTE: Note = {
  id: 5,
  title: 'Конспект: индексы',
  bodyMarkdown: [
    '# Когда какой индекс',
    '',
    '**B-tree** — сравнения и сортировка.',
    '',
    '- B-tree — равенство',
    '- GIN — массивы',
  ].join('\n'),
  tags: ['учёба', 'базы данных'],
  createdAt: localIso(2026, 9, 1, 10, 2),
  updatedAt: localIso(2026, 9, 8, 20, 15),
};

/** Мини-«сервер»: заметки в памяти, GET/PATCH/DELETE по id, список. */
function makeServer(initial: Note[]) {
  const notes = [...initial];
  return (url: string, init: RequestInit): Response => {
    const method = init.method ?? 'GET';

    if (url.endsWith('/api/auth/me')) {
      return json(200, { user: { id: 1, email: 'user@example.com' } });
    }
    if (url.endsWith('/api/tags')) {
      return json(200, { items: [] });
    }

    const byId = url.match(/^\/api\/notes\/(\d+)$/);
    if (byId) {
      const id = Number(byId[1]);
      const note = notes.find((item) => item.id === id);
      if (!note) {
        return json(404, { error: { code: 'NOT_FOUND', message: 'Заметка не найдена' } });
      }
      if (method === 'DELETE') {
        return noContent(204);
      }
      return json(200, note);
    }

    if (url === '/api/notes' || url.startsWith('/api/notes?')) {
      return json(200, { items: notes, total: notes.length });
    }

    throw new Error(`Неожиданный запрос: ${method} ${url}`);
  };
}

function renderNote(id: string | number) {
  return render(
    <MemoryRouter initialEntries={[`/notes/${id}`]}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </MemoryRouter>,
  );
}

/** Отрендеренная статья markdown (`article.md`). */
function articleEl(): HTMLElement {
  const el = document.querySelector<HTMLElement>('article.md');
  if (!el) throw new Error('Нет article.md');
  return el;
}

beforeEach(() => {
  window.localStorage.clear();
  delete (window as unknown as { __pwned?: unknown }).__pwned;
});

/* --------------------------------- тесты ---------------------------------- */

describe('просмотр заметки (S5)', () => {
  it('открывает заметку и рендерит markdown + сохранённое содержимое (AC-11/AC-18/AC-31)', async () => {
    setupFetch(makeServer([NOTE]));
    renderNote(NOTE.id);

    // Заголовок заметки — h1 страницы.
    expect(
      await screen.findByRole('heading', { level: 1, name: 'Конспект: индексы' }),
    ).toBeInTheDocument();

    // markdown отрендерен: маркеры преобразованы в элементы.
    const strong = screen.getByText('B-tree');
    expect(strong.tagName).toBe('STRONG');
    expect(articleEl().textContent).not.toContain('**');
    expect(within(articleEl()).getByText('B-tree — равенство')).toBeInTheDocument();

    // Мета: дата в формате просмотра и <time datetime>.
    const updated = screen.getByText('8 окт 2026, 20:15');
    expect(updated.tagName).toBe('TIME');
    expect(updated).toHaveAttribute('datetime', NOTE.updatedAt);

    // Теги — текстом.
    expect(screen.getByText('учёба')).toBeInTheDocument();
    expect(screen.getByText('базы данных')).toBeInTheDocument();
  });

  it('чужой/несуществующий id → «Заметка не найдена», содержимое не раскрывается (AC-11/Q-A7)', async () => {
    // Заметка 999 не принадлежит пользователю (сервер отдаёт 404 — как для чужой).
    setupFetch(makeServer([NOTE]));
    renderNote(999);

    expect(await screen.findByText('Заметка не найдена')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'К моим заметкам' })).toBeInTheDocument();
    // Данные чужой/несуществующей заметки не показаны.
    expect(screen.queryByText('Конспект: индексы')).not.toBeInTheDocument();
    expect(document.querySelector('article.md')).toBeNull();
  });

  it('теги и заголовок — текст: HTML-подобные символы не исполняются (AC-47/NFR-14)', async () => {
    const dangerous: Note = {
      id: 8,
      title: 'Заголовок <img src=x onerror="window.__pwned=1">',
      bodyMarkdown: 'Обычный текст',
      tags: ['<script>window.__pwned=1</script>', '<b>жирный</b>'],
      createdAt: NOTE.createdAt,
      updatedAt: NOTE.updatedAt,
    };
    setupFetch(makeServer([dangerous]));
    renderNote(dangerous.id);

    const h1 = await screen.findByRole('heading', { level: 1 });
    // Заголовок показан как текст (символы экранированы, узлов img/script нет).
    expect(h1.textContent).toContain('<img src=x onerror=');
    expect(document.querySelector('h1 img')).toBeNull();

    // Теги — обычный текст, не HTML.
    expect(screen.getByText('<script>window.__pwned=1</script>')).toBeInTheDocument();
    expect(screen.getByText('<b>жирный</b>')).toBeInTheDocument();
    expect(document.querySelector('.tag__label script')).toBeNull();
    expect(document.querySelector('.tag__label b')).toBeNull();

    expect((window as unknown as { __pwned?: unknown }).__pwned).toBeUndefined();
  });

  it('один h1 на страницу; markdown-заголовки начинаются с h2 (DESIGN §5.4)', async () => {
    setupFetch(makeServer([NOTE]));
    renderNote(NOTE.id);

    await screen.findByRole('heading', { level: 1, name: 'Конспект: индексы' });

    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
    // markdown `#` → h2 внутри статьи; h1 в статье нет.
    const article = articleEl();
    expect(
      within(article).getByRole('heading', { level: 2, name: 'Когда какой индекс' }),
    ).toBeInTheDocument();
    expect(within(article).queryAllByRole('heading', { level: 1 })).toHaveLength(0);
  });

  it('удаление из просмотра → подтверждение → возврат к списку (AC-21/E13)', async () => {
    setupFetch(makeServer([NOTE]));
    const user = userEvent.setup();
    renderNote(NOTE.id);

    await screen.findByRole('heading', { level: 1, name: 'Конспект: индексы' });
    await user.click(screen.getByRole('button', { name: 'Удалить' }));

    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByRole('heading', { name: 'Удалить заметку?' }),
    ).toBeInTheDocument();
    expect(within(dialog).getByText(/Конспект: индексы/)).toBeInTheDocument();

    await user.click(within(dialog).getByRole('button', { name: 'Удалить заметку' }));

    // Возврат к списку (S3) — заголовок списка виден.
    expect(await screen.findByRole('heading', { level: 1, name: 'Мои заметки' })).toBeInTheDocument();
    const call = fetchMock.mock.calls.find(
      ([url, init]) => String(url) === `/api/notes/${NOTE.id}` && (init as RequestInit)?.method === 'DELETE',
    );
    expect(call).toBeTruthy();
  });

  it('отмена в диалоге удаления не шлёт DELETE и не уводит со страницы', async () => {
    setupFetch(makeServer([NOTE]));
    const user = userEvent.setup();
    renderNote(NOTE.id);

    await screen.findByRole('heading', { level: 1, name: 'Конспект: индексы' });
    await user.click(screen.getByRole('button', { name: 'Удалить' }));
    await screen.findByRole('dialog');
    await user.click(screen.getByRole('button', { name: 'Отмена' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(screen.getByRole('heading', { level: 1, name: 'Конспект: индексы' })).toBeInTheDocument();
    expect(
      fetchMock.mock.calls.some(([, init]) => (init as RequestInit)?.method === 'DELETE'),
    ).toBe(false);
  });

  it('ссылка «Мои заметки» и действие «Редактировать» ведут на нужные маршруты', async () => {
    setupFetch(makeServer([NOTE]));
    renderNote(NOTE.id);

    await screen.findByRole('heading', { level: 1, name: 'Конспект: индексы' });
    expect(screen.getByRole('link', { name: /Мои заметки/ })).toHaveAttribute('href', '/notes');
    expect(screen.getByRole('link', { name: /Редактировать/ })).toHaveAttribute(
      'href',
      `/notes/${NOTE.id}/edit`,
    );
  });

  it('загрузка — скелетон статьи, а не спиннер (DESIGN §4.2.1)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) {
        return json(200, { user: { id: 1, email: 'user@example.com' } });
      }
      return new Promise<Response>(() => {
        /* заметка «висит» — показываем скелетон */
      });
    });
    renderNote(NOTE.id);

    expect(await screen.findByText('Загрузка заметки…')).toBeInTheDocument();
    expect(document.querySelectorAll('.skeleton').length).toBeGreaterThan(0);
    expect(document.querySelector('article.md')).toBeNull();
  });
});
