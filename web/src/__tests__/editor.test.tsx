/**
 * editor.test.tsx — сценарии T-09: экран редактора (S4).
 *
 * Покрытие приёмки: создание заметки (заголовок+текст+теги) → POST персистентно;
 * пустая → запрет сохранения; markdown хранится как raw и рендерится в превью;
 * toolbar вставляет синтаксис с учётом выделения без дублирования маркеров;
 * live-сплит/табы; несохранённые правки → предупреждение (диалог + beforeunload);
 * ошибка сохранения не теряет текст.
 *
 * `fetch` мокается целиком, ответы строятся как на сервере (PLAN §3.2).
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import App from '../App';
import { AuthProvider } from '../auth/AuthContext';
import type { Note, TagCount } from '../api/notes';

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

const TAGS: TagCount[] = [
  { name: 'работа', count: 1 },
  { name: 'планы', count: 2 },
];

const SAVED_NOTE: Note = {
  id: 7,
  title: 'Старое название',
  bodyMarkdown: '**старый** текст',
  tags: ['работа'],
  createdAt: '2026-10-10T08:00:00.000Z',
  updatedAt: '2026-10-12T08:00:00.000Z',
};

/** Мини-«сервер» заметок с персистентностью в памяти. */
function makeServer(initial: Note[]) {
  let notes = [...initial];
  let nextId = Math.max(0, ...notes.map((note) => note.id)) + 1;

  return (url: string, init: RequestInit): Response => {
    const method = init.method ?? 'GET';

    if (url.endsWith('/api/auth/me')) {
      return json(200, { user: { id: 1, email: 'user@example.com' } });
    }
    if (url.endsWith('/api/tags')) {
      return json(200, { items: TAGS });
    }

    const byId = url.match(/^\/api\/notes\/(\d+)$/);
    if (byId) {
      const id = Number(byId[1]);
      const index = notes.findIndex((note) => note.id === id);
      if (index === -1) {
        return json(404, { error: { code: 'NOT_FOUND', message: 'Заметка не найдена' } });
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(String(init.body)) as Partial<Note>;
        notes[index] = { ...notes[index], ...patch, updatedAt: '2026-10-13T10:00:00.000Z' };
        return json(200, notes[index]);
      }
      if (method === 'DELETE') return noContent(204);
      return json(200, notes[index]);
    }

    if (url === '/api/notes' || url.startsWith('/api/notes?')) {
      if (method === 'POST') {
        const body = JSON.parse(String(init.body)) as Partial<Note>;
        const created: Note = {
          id: nextId++,
          title: body.title ?? null,
          bodyMarkdown: body.bodyMarkdown ?? '',
          tags: body.tags ?? [],
          createdAt: '2026-10-13T10:00:00.000Z',
          updatedAt: '2026-10-13T10:00:00.000Z',
        };
        notes = [created, ...notes];
        return json(201, created);
      }
      return json(200, { items: notes, total: notes.length });
    }

    throw new Error(`Неожиданный запрос: ${method} ${url}`);
  };
}

function callsTo(method: string): [string, RequestInit][] {
  return fetchMock.mock.calls
    .map((call) => [String(call[0]), (call[1] ?? {}) as RequestInit] as [string, RequestInit])
    .filter(([, init]) => (init.method ?? 'GET') === method);
}

function renderEditor(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </MemoryRouter>,
  );
}

const bodyOf = (init: RequestInit): Record<string, unknown> =>
  JSON.parse(String(init.body)) as Record<string, unknown>;

beforeEach(() => {
  window.localStorage.clear();
});

/* --------------------------------- тесты ---------------------------------- */

describe('создание заметки', () => {
  it('заголовок + текст + теги → POST, персистентно (AC-16/AC-33)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await screen.findByRole('heading', { name: 'Новая заметка' });
    await user.type(screen.getByLabelText('Заголовок — необязательно'), 'План на неделю');
    await user.type(screen.getByLabelText('Текст заметки в markdown'), 'Текст заметки');

    const tagInput = screen.getByLabelText('Теги');
    await user.type(tagInput, 'работа{Enter}');
    await user.type(tagInput, 'планы,');

    expect(screen.getByRole('button', { name: 'Убрать тег «работа»' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Убрать тег «планы»' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    await waitFor(() => expect(callsTo('POST')).toHaveLength(1));
    const [url, init] = callsTo('POST')[0];
    expect(url).toBe('/api/notes');
    expect(bodyOf(init)).toEqual({
      title: 'План на неделю',
      bodyMarkdown: 'Текст заметки',
      tags: ['работа', 'планы'],
    });

    expect(await screen.findByText(/Сохранено/)).toBeInTheDocument();
  });

  it('пустая заметка → запрет сохранения с сообщением, POST не отправляется (AC-17/E1)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await screen.findByRole('heading', { name: 'Новая заметка' });
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    expect(await screen.findByText('Заметка пустая')).toBeInTheDocument();
    expect(callsTo('POST')).toHaveLength(0);
  });
});

describe('markdown и превью', () => {
  it('markdown хранится как raw, превью рендерит форматирование (AC-28/AC-29)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText('Текст заметки в markdown');
    const raw = '# Заголовок\n\n**жирный** текст';
    await user.click(textarea);
    await user.paste(raw);

    expect(textarea).toHaveValue(raw);
    expect(screen.getByText(`${raw.length} / 100 000`)).toBeInTheDocument();

    const preview = document.querySelector('[data-preview]');
    expect(preview).not.toBeNull();
    expect(preview!.querySelector('strong')?.textContent).toBe('жирный');
    // Заголовок markdown рендерится как h2 (h1 зарезервирован под заголовок заметки).
    expect(preview!.querySelector('h2')?.textContent).toBe('Заголовок');
    expect(preview!.querySelector('h1')).toBeNull();
  });

  it('пустое превью показывает подсказку «Ничего не набрано»', async () => {
    setupFetch(makeServer([]));
    renderEditor('/notes/new');
    await screen.findByRole('heading', { name: 'Новая заметка' });
    expect(screen.getByText('Ничего не набрано')).toBeInTheDocument();
  });
});

describe('toolbar форматирования', () => {
  it('префикс вставляется к строке курсора и не дублируется', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText('Текст заметки в markdown');
    await user.type(textarea, 'Заголовок');

    await user.click(screen.getByRole('button', { name: 'Заголовок первого уровня' }));
    expect(textarea).toHaveValue('# Заголовок');

    await user.click(screen.getByRole('button', { name: 'Заголовок первого уровня' }));
    expect(textarea).toHaveValue('# Заголовок');
  });

  it('обёртка применяется к выделению; повторный клик снимает её (без дубликатов)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText<HTMLTextAreaElement>(
      'Текст заметки в markdown',
    );
    await user.type(textarea, 'мир');
    textarea.focus();
    textarea.setSelectionRange(0, 3);

    await user.click(screen.getByRole('button', { name: 'Жирный' }));
    expect(textarea).toHaveValue('**мир**');

    textarea.focus();
    textarea.setSelectionRange(2, 5);
    await user.click(screen.getByRole('button', { name: 'Жирный' }));
    expect(textarea).toHaveValue('мир');
  });

  it('блок кода огораживается, ссылка вставляется по выделению', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText<HTMLTextAreaElement>(
      'Текст заметки в markdown',
    );

    await user.click(screen.getByRole('button', { name: 'Блок кода' }));
    expect(textarea).toHaveValue('```\nкод\n```');

    await user.clear(textarea);
    await user.type(textarea, 'спека');
    textarea.focus();
    textarea.setSelectionRange(0, 5);
    await user.click(screen.getByRole('button', { name: 'Ссылка' }));
    expect(textarea).toHaveValue('[спека](https://)');
  });

  it('при клике мышью фокус возвращается в textarea', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText('Текст заметки в markdown');
    await user.type(textarea, 'abc');
    await user.click(screen.getByRole('button', { name: 'Курсив' }));

    expect(textarea).toHaveFocus();
  });

  it('toolbar доступен: role=toolbar, группы, aria-label на кнопках (DESIGN §2.7)', async () => {
    setupFetch(makeServer([]));
    renderEditor('/notes/new');
    await screen.findByRole('heading', { name: 'Новая заметка' });

    expect(screen.getByRole('toolbar', { name: 'Форматирование markdown' })).toBeInTheDocument();
    expect(screen.getAllByRole('group').length).toBeGreaterThanOrEqual(4);
    expect(screen.getByRole('button', { name: 'Нумерованный список' })).toHaveAttribute(
      'title',
      'Нумерованный список',
    );
  });
});

describe('сплит и табы (AC-30/NFR-23)', () => {
  it('на узких экранах табы переключают редактор/превью', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await screen.findByRole('heading', { name: 'Новая заметка' });
    const shell = document.querySelector('.editor-shell');
    expect(shell).toHaveAttribute('data-editor-mode', 'editor');
    // Обе панели в DOM (широкий экран — сплит, узкий — CSS скрывает одну).
    expect(screen.getByRole('tabpanel', { name: 'Редактор' })).toBeInTheDocument();
    expect(screen.getByRole('tabpanel', { name: 'Просмотр' })).toBeInTheDocument();

    await user.click(screen.getByRole('tab', { name: 'Просмотр' }));
    expect(shell).toHaveAttribute('data-editor-mode', 'preview');
    expect(screen.getByRole('tab', { name: 'Просмотр' })).toHaveAttribute('aria-selected', 'true');
  });

  it('ArrowRight переключает панели и переносит фокус (NFR-16)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await screen.findByRole('heading', { name: 'Новая заметка' });
    const editorTab = screen.getByRole('tab', { name: 'Редактор' });
    editorTab.focus();
    await user.keyboard('{ArrowRight}');

    expect(screen.getByRole('tab', { name: 'Просмотр' })).toHaveFocus();
    expect(document.querySelector('.editor-shell')).toHaveAttribute('data-editor-mode', 'preview');
  });
});

describe('несохранённые изменения', () => {
  it('диалог при уходе: остаться / выйти без сохранения (AC-20/E10)', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await user.type(
      await screen.findByLabelText('Текст заметки в markdown'),
      'черновик',
    );
    expect(screen.getByText(/Есть несохранённые изменения/)).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Отмена' }));
    let dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Есть несохранённые изменения')).toBeInTheDocument();

    await user.click(within(dialog).getByRole('button', { name: 'Остаться в редакторе' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());

    await user.click(screen.getByRole('button', { name: 'Отмена' }));
    dialog = await screen.findByRole('dialog');
    await user.click(within(dialog).getByRole('button', { name: 'Выйти без сохранения' }));

    expect(await screen.findByRole('heading', { name: 'Мои заметки' })).toBeInTheDocument();
  });

  it('«Сохранить и выйти» сохраняет и уводит к списку', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await user.type(
      await screen.findByLabelText('Текст заметки в markdown'),
      'важный текст',
    );
    await user.click(screen.getByRole('button', { name: 'Отмена' }));
    const dialog = await screen.findByRole('dialog');
    await user.click(within(dialog).getByRole('button', { name: 'Сохранить и выйти' }));

    await waitFor(() => expect(callsTo('POST')).toHaveLength(1));
    expect(bodyOf(callsTo('POST')[0][1]).bodyMarkdown).toBe('важный текст');
    expect(await screen.findByRole('heading', { name: 'Мои заметки' })).toBeInTheDocument();
  });

  it('beforeunload предотвращается при несохранённых правках', async () => {
    setupFetch(makeServer([]));
    const user = userEvent.setup();
    renderEditor('/notes/new');

    await user.type(await screen.findByLabelText('Текст заметки в markdown'), 'x');

    const event = new Event('beforeunload', { cancelable: true });
    window.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
  });
});

describe('ошибка сохранения', () => {
  it('текст не теряется, статус не «сохранено» (E17)', async () => {
    const base = makeServer([]);
    setupFetch((url, init) => {
      if (url === '/api/notes' && (init.method ?? 'GET') === 'POST') {
        return json(500, { error: { code: 'INTERNAL', message: 'Сбой' } });
      }
      return base(url, init);
    });
    const user = userEvent.setup();
    renderEditor('/notes/new');

    const textarea = await screen.findByLabelText('Текст заметки в markdown');
    await user.type(textarea, 'важный текст');
    await user.type(screen.getByLabelText('Заголовок — необязательно'), 'Заголовок');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    expect(await screen.findByText('Не удалось сохранить')).toBeInTheDocument();
    expect(textarea).toHaveValue('важный текст');
    expect(screen.queryByText(/Сохранено/)).not.toBeInTheDocument();
  });
});

describe('редактирование заметки', () => {
  it('загружает существующую заметку в поля (AC-31)', async () => {
    setupFetch(makeServer([SAVED_NOTE]));
    renderEditor('/notes/7/edit');

    await waitFor(() =>
      expect(screen.getByLabelText('Заголовок — необязательно')).toHaveValue('Старое название'),
    );
    expect(screen.getByLabelText('Текст заметки в markdown')).toHaveValue('**старый** текст');
    expect(screen.getByRole('button', { name: 'Убрать тег «работа»' })).toBeInTheDocument();
    expect(screen.getByText(/Сохранено/)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Редактирование заметки' })).toBeInTheDocument();
  });

  it('сохранение изменений → PATCH (AC-33)', async () => {
    setupFetch(makeServer([SAVED_NOTE]));
    const user = userEvent.setup();
    renderEditor('/notes/7/edit');

    const titleInput = await screen.findByDisplayValue('Старое название');
    await user.clear(titleInput);
    await user.type(titleInput, 'Новое название');
    await user.click(screen.getByRole('button', { name: 'Сохранить' }));

    await waitFor(() => expect(callsTo('PATCH')).toHaveLength(1));
    const [url, init] = callsTo('PATCH')[0];
    expect(url).toBe('/api/notes/7');
    expect(bodyOf(init)).toMatchObject({
      title: 'Новое название',
      bodyMarkdown: '**старый** текст',
      tags: ['работа'],
    });
    expect(await screen.findByText(/Сохранено/)).toBeInTheDocument();
  });

  it('несуществующая заметка → сообщение об ошибке загрузки', async () => {
    setupFetch(makeServer([]));
    renderEditor('/notes/999/edit');

    expect(await screen.findByText('Не удалось загрузить заметку')).toBeInTheDocument();
  });
});
