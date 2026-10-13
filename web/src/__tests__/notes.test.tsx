/**
 * notes.test.tsx — сценарии T-08: экран списка заметок (S3).
 *
 * Покрытие приёмки: список своих заметок; переключение плитки↔список без изменения
 * состава; сохранение вида в localStorage (дефолт grid); серверный поиск с debounce;
 * чип тега фильтрует; q+tag по «И»; «Сбросить»; empty-state A/B; удаление с
 * подтверждением/отменой; скелетоны и ошибка с «Повторить».
 *
 * `fetch` мокается целиком; ответы строятся по query-параметрам URL, как на сервере.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import App from '../App';
import { AuthProvider } from '../auth/AuthContext';
import type { Note, TagCount } from '../api/notes';
import { VIEW_STORAGE_KEY } from '../lib/view';

/* ------------------------------- окружение -------------------------------- */

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    headers: { get: (name: string) => headers[name.toLowerCase()] ?? null },
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

const NOTES: Note[] = [
  {
    id: 1,
    title: 'План на неделю',
    bodyMarkdown: 'Доработать поиск по заметкам\nРевью макетов интерфейса',
    tags: ['работа', 'планы'],
    createdAt: '2026-10-10T08:00:00.000Z',
    updatedAt: '2026-10-13T09:20:00.000Z',
  },
  {
    id: 2,
    title: 'Рецепт борща',
    bodyMarkdown: 'Свёкла, капуста, бульон. Варить 40 минут, добавить сметану.',
    tags: ['рецепты'],
    createdAt: '2026-10-11T10:00:00.000Z',
    updatedAt: '2026-10-12T18:04:00.000Z',
  },
  {
    id: 3,
    title: null,
    bodyMarkdown: 'Купить: молоко, хлеб, кофе\nСписок покупок на выходные',
    tags: [],
    createdAt: '2026-10-05T07:00:00.000Z',
    updatedAt: '2026-10-05T08:10:00.000Z',
  },
];

const TAGS: TagCount[] = [
  { name: 'работа', count: 1 },
  { name: 'планы', count: 1 },
  { name: 'рецепты', count: 1 },
];

/** Повторяет серверную фильтрацию `?q=&tag=` (подстрочно, «И»). */
function filterNotes(notes: Note[], url: string): Note[] {
  const params = new URL(`http://localhost${url}`).searchParams;
  const q = (params.get('q') ?? '').toLowerCase();
  const tag = params.get('tag');
  let items = notes;
  if (q) {
    items = items.filter((note) =>
      `${note.title ?? ''}\n${note.bodyMarkdown}`.toLowerCase().includes(q),
    );
  }
  if (tag) {
    items = items.filter((note) =>
      note.tags.some((value) => value.toLowerCase() === tag.toLowerCase()),
    );
  }
  return items;
}

/** Базовый обработчик: auth/me, заметки (GET/DELETE), теги. */
function notesRoute(notes: Note[], tags: TagCount[]): FetchHandler {
  return (url, init) => {
    if (url.endsWith('/api/auth/me')) {
      return json(200, { user: { id: 1, email: 'user@example.com' } });
    }
    if (/^\/api\/notes\/\d+$/.test(url) && init.method === 'DELETE') {
      return noContent(204);
    }
    if (url.startsWith('/api/notes') && (init.method ?? 'GET') === 'GET') {
      const items = filterNotes(notes, url);
      return json(200, { items, total: items.length });
    }
    if (url.endsWith('/api/tags')) {
      return json(200, { items: tags });
    }
    throw new Error(`Неожиданный запрос: ${init.method ?? 'GET'} ${url}`);
  };
}

function renderNotes() {
  return render(
    <MemoryRouter initialEntries={['/notes']}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </MemoryRouter>,
  );
}

async function findList() {
  return screen.findByRole('list', { name: 'Список заметок' });
}

/** Ждёт появления блока пустого состояния по data-атрибуту. */
async function findEmptyState(attr: 'data-empty-nonotes' | 'data-empty-noresults') {
  return waitFor(() => {
    const el = document.querySelector<HTMLElement>(`[${attr}]`);
    if (!el) throw new Error(`Нет пустого состояния [${attr}]`);
    return el;
  });
}

/** Последний URL запроса к списку заметок. */
function lastNotesUrl(): string {
  const calls = fetchMock.mock.calls
    .map(([url]) => String(url))
    .filter((url) => url.startsWith('/api/notes') && !/\/api\/notes\/\d+/.test(url));
  return calls[calls.length - 1] ?? '';
}

beforeEach(() => {
  window.localStorage.clear();
});

/* --------------------------------- тесты ---------------------------------- */

describe('список заметок', () => {
  it('показывает свои заметки (плитки по умолчанию)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    renderNotes();

    const list = await findList();
    expect(list).toHaveClass('results--grid');
    expect(within(list).getAllByRole('listitem')).toHaveLength(3);

    expect(screen.getByText('План на неделю')).toBeInTheDocument();
    expect(screen.getByText('Рецепт борща')).toBeInTheDocument();
    // Заметка без заголовка — заголовком стала первая строка текста (E3).
    expect(screen.getByText('Купить: молоко, хлеб, кофе')).toBeInTheDocument();
    expect(screen.getByText('Без тегов')).toBeInTheDocument();
  });

  it('фрагмент — plain-text без рендера markdown, дата в <time datetime>', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    renderNotes();

    await findList();
    const snippet = screen.getByText(/Доработать поиск по заметкам/);
    expect(snippet).toHaveClass('note-item__snippet');

    const time = document.querySelector('time.note-item__date');
    expect(time).toHaveAttribute('datetime', '2026-10-13T09:20:00.000Z');
  });
});

describe('переключатель вида', () => {
  it('переключает плитки↔список без изменения состава и порядка (AC-24/AC-26)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    const grid = await findList();
    const before = within(grid)
      .getAllByRole('listitem')
      .map((item) => item.textContent);

    await user.click(screen.getByRole('button', { name: 'Список' }));
    const list = screen.getByRole('list', { name: 'Список заметок' });
    expect(list).toHaveClass('results--list');
    expect(list).not.toHaveClass('results--grid');
    expect(
      within(list)
        .getAllByRole('listitem')
        .map((item) => item.textContent),
    ).toEqual(before);

    await user.click(screen.getByRole('button', { name: 'Плитки' }));
    expect(screen.getByRole('list', { name: 'Список заметок' })).toHaveClass('results--grid');
  });

  it('выбор вида сохраняется в localStorage, дефолт grid (AC-25/AC-27)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    const first = renderNotes();

    await findList();
    expect(screen.getByRole('list', { name: 'Список заметок' })).toHaveClass('results--grid');
    expect(window.localStorage.getItem(VIEW_STORAGE_KEY)).toBeNull();

    await user.click(screen.getByRole('button', { name: 'Список' }));
    expect(window.localStorage.getItem(VIEW_STORAGE_KEY)).toBe('list');
    first.unmount();

    // Восстановление после «перезагрузки».
    renderNotes();
    await findList();
    expect(screen.getByRole('list', { name: 'Список заметок' })).toHaveClass('results--list');
  });

  it('повреждённое значение notes.view трактуется как grid', async () => {
    window.localStorage.setItem(VIEW_STORAGE_KEY, 'weird');
    setupFetch(notesRoute(NOTES, TAGS));
    renderNotes();

    await findList();
    expect(screen.getByRole('list', { name: 'Список заметок' })).toHaveClass('results--grid');
  });

  it('ArrowLeft/ArrowRight переключают вид и переносят фокус (NFR-16)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    screen.getByRole('button', { name: 'Плитки' }).focus();
    await user.keyboard('{ArrowRight}');

    const listButton = screen.getByRole('button', { name: 'Список' });
    expect(listButton).toHaveAttribute('aria-pressed', 'true');
    expect(listButton).toHaveFocus();
    expect(screen.getByRole('list', { name: 'Список заметок' })).toHaveClass('results--list');

    await user.keyboard('{ArrowLeft}');
    expect(screen.getByRole('button', { name: 'Плитки' })).toHaveFocus();
  });
});

describe('поиск и фильтры', () => {
  it('поиск с debounce фильтрует серверно через ?q=', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.type(screen.getByLabelText('Поиск по заметкам'), 'борщ');

    await waitFor(() => expect(lastNotesUrl()).toContain('q='));
    expect(await screen.findByText('Рецепт борща')).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByText('План на неделю')).not.toBeInTheDocument());
  });

  it('чип тега фильтрует и переключает aria-pressed через ?tag=', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    const chip = await screen.findByRole('button', { name: 'работа' });
    await user.click(chip);

    expect(chip).toHaveAttribute('aria-pressed', 'true');
    await waitFor(() => expect(lastNotesUrl()).toContain('tag='));
    expect(await screen.findByText('План на неделю')).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByText('Рецепт борща')).not.toBeInTheDocument());

    // Повторный клик снимает фильтр.
    await user.click(chip);
    expect(chip).toHaveAttribute('aria-pressed', 'false');
    expect(await screen.findByText('Рецепт борща')).toBeInTheDocument();
  });

  it('q и tag комбинируются по «И» (пересечение)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.type(screen.getByLabelText('Поиск по заметкам'), 'Доработать');
    await waitFor(() => expect(lastNotesUrl()).toContain('q='));

    await user.click(await screen.findByRole('button', { name: 'рецепты' }));

    await waitFor(() => {
      expect(lastNotesUrl()).toContain('q=');
      expect(lastNotesUrl()).toContain('tag=');
    });
    // «Доработать» (заметка 1) ∩ тег «рецепты» (заметка 2) = пусто.
    expect(await screen.findByText('Ничего не найдено')).toBeInTheDocument();
  });

  it('«Сбросить» очищает поиск и тег и возвращает все заметки', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.type(screen.getByLabelText('Поиск по заметкам'), 'борщ');
    await screen.findByText('Рецепт борща');
    await user.click(await screen.findByRole('button', { name: 'работа' }));
    await screen.findByText('Ничего не найдено');

    await user.click(screen.getByRole('button', { name: 'Сбросить поиск и фильтры' }));

    expect(await screen.findByText('План на неделю')).toBeInTheDocument();
    expect(screen.getByText('Рецепт борща')).toBeInTheDocument();
    expect(screen.getByLabelText('Поиск по заметкам')).toHaveValue('');
    expect(lastNotesUrl()).not.toContain('q=');
    expect(lastNotesUrl()).not.toContain('tag=');
  });

  it('кнопка очистки поиска очищает запрос и возвращает фокус', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    const input = screen.getByLabelText('Поиск по заметкам');
    await user.type(input, 'борщ');
    await screen.findByText('Рецепт борща');

    await user.click(screen.getByRole('button', { name: 'Очистить поиск' }));

    expect(input).toHaveValue('');
    expect(input).toHaveFocus();
    expect(await screen.findByText('План на неделю')).toBeInTheDocument();
  });
});

describe('пустые состояния', () => {
  it('A: нет заметок и нет фильтров → «Пока ни одной заметки» + CTA', async () => {
    setupFetch(notesRoute([], []));
    renderNotes();

    const block = await findEmptyState('data-empty-nonotes');
    expect(within(block).getByText('Пока ни одной заметки')).toBeInTheDocument();
    expect(within(block).getByRole('link', { name: 'Создать заметку' })).toBeInTheDocument();
    expect(screen.queryByText('Ничего не найдено')).not.toBeInTheDocument();
  });

  it('B: пусто при активном поиске → «Ничего не найдено» + «Сбросить»', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.type(screen.getByLabelText('Поиск по заметкам'), 'несуществующая-строка-zzz');

    expect(await screen.findByText('Ничего не найдено')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Сбросить поиск и фильтры' })).toBeInTheDocument();
    expect(screen.queryByText('Пока ни одной заметки')).not.toBeInTheDocument();
  });
});

describe('удаление', () => {
  it('подтверждение удаляет заметку без перезагрузки (AC-21)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.click(
      screen.getByRole('button', { name: 'Удалить заметку «План на неделю»' }),
    );

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByRole('heading', { name: 'Удалить заметку?' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Удалить заметку' }));

    await waitFor(() => expect(screen.queryByText('План на неделю')).not.toBeInTheDocument());
    expect(screen.getByText('Рецепт борща')).toBeInTheDocument();
    const call = fetchMock.mock.calls.find(
      ([url, init]) => String(url) === '/api/notes/1' && (init as RequestInit)?.method === 'DELETE',
    );
    expect(call).toBeTruthy();
  });

  it('отмена не удаляет заметку и не шлёт DELETE (AC-22)', async () => {
    setupFetch(notesRoute(NOTES, TAGS));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.click(screen.getByRole('button', { name: 'Удалить заметку «Рецепт борща»' }));
    await screen.findByRole('dialog');

    await user.click(screen.getByRole('button', { name: 'Отмена' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(screen.getByText('Рецепт борща')).toBeInTheDocument();
    expect(
      fetchMock.mock.calls.some(
        ([, init]) => (init as RequestInit)?.method === 'DELETE',
      ),
    ).toBe(false);
  });

  it('удаление последней заметки показывает empty-state A (E14)', async () => {
    setupFetch(notesRoute([NOTES[1]], [TAGS[2]]));
    const user = userEvent.setup();
    renderNotes();

    await findList();
    await user.click(screen.getByRole('button', { name: 'Удалить заметку «Рецепт борща»' }));
    await screen.findByRole('dialog');
    await user.click(screen.getByRole('button', { name: 'Удалить заметку' }));

    const block = await findEmptyState('data-empty-nonotes');
    expect(within(block).getByText('Пока ни одной заметки')).toBeInTheDocument();
    expect(within(block).getByRole('link', { name: 'Создать заметку' })).toBeInTheDocument();
  });
});

describe('состояния загрузки и ошибки', () => {
  it('загрузка — скелетоны, а не спиннер (§4.2.1)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) {
        return json(200, { user: { id: 1, email: 'user@example.com' } });
      }
      return new Promise<Response>(() => {
        /* список «висит» — показываем скелетоны */
      });
    });
    renderNotes();

    expect(await screen.findByText('Загрузка заметок…')).toBeInTheDocument();
    expect(document.querySelectorAll('.skeleton').length).toBeGreaterThan(0);
    expect(screen.queryByRole('list', { name: 'Список заметок' })).not.toBeInTheDocument();
  });

  it('ошибка загрузки → алерт с «Повторить», повтор успешен (§4.2.3)', async () => {
    let fail = true;
    const base = notesRoute(NOTES, TAGS);
    setupFetch((url, init) => {
      if (url.startsWith('/api/notes') && (init.method ?? 'GET') === 'GET' && fail) {
        return json(500, { error: { code: 'INTERNAL', message: 'Сбой' } });
      }
      return base(url, init);
    });
    const user = userEvent.setup();
    renderNotes();

    expect(await screen.findByText('Не удалось загрузить заметки')).toBeInTheDocument();

    fail = false;
    await user.click(screen.getByRole('button', { name: 'Повторить' }));

    expect(await screen.findByText('План на неделю')).toBeInTheDocument();
  });
});
