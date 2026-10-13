/**
 * a11y.test.tsx — сквозной пас доступности и клавиатуры (T-11, DESIGN §5, NFR-15..20).
 *
 * Проверяется контракт aria (DESIGN §5.2) и клавиатура (§5.3) на **всех** экранах:
 *   * Login/Register — формы, ошибки полей (`aria-invalid`/`aria-describedby`/`role=alert`),
 *     skip-link, один `h1`, декоративные иконки;
 *   * Notes — segmented (group/aria-pressed/status), поиск (sr-only label + describedby),
 *     чипы (group/aria-pressed/счётчик aria-hidden), регион результатов, empty-state,
 *     диалог удаления (Esc + возврат фокуса);
 *   * Editor — toolbar (toolbar/group/separator/aria-label/title/keyshortcuts),
 *     табы Редактор/Просмотр (tablist/tab/tabpanel/roving tabindex/Arrow),
 *     поле тегов (label/aria-invalid/role=alert), диалог несохранённых правок;
 *   * Note — один `h1`, теги текстом, диалог удаления, состояния 404/ошибки с заголовком;
 *   * сквозной `Tab`-обход без «залипания».
 *
 * Всё — через роли/имена/фокус, без привязки к CSS-классам (проверка того, что «видит»
 * вспомогательная технология). CSS-контракт адаптива — в `a11y-css.test.ts`.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import App from '../App';
import { AuthProvider } from '../auth/AuthContext';
import type { Note, TagCount } from '../api/notes';

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
type Entry = string | { pathname: string; state?: unknown };

let fetchMock: ReturnType<typeof vi.fn>;

function setupFetch(handler: FetchHandler): void {
  fetchMock = vi.fn(async (input: unknown, init?: RequestInit) => {
    const url =
      typeof input === 'string' ? input : String((input as { url?: string })?.url ?? input);
    return handler(url, init ?? {});
  });
  vi.stubGlobal('fetch', fetchMock);
}

const ME = { user: { id: 1, email: 'user@example.com' } };
const UNAUTHORIZED = { error: { code: 'UNAUTHORIZED', message: 'Требуется авторизация' } };

const NOTES: Note[] = [
  {
    id: 1,
    title: 'План на неделю',
    bodyMarkdown: 'Доработать поиск по заметкам',
    tags: ['работа'],
    createdAt: '2026-10-10T08:00:00.000Z',
    updatedAt: '2026-10-13T09:20:00.000Z',
  },
  {
    id: 2,
    title: 'Рецепт борща',
    bodyMarkdown: 'Свёкла, капуста, бульон.',
    tags: ['рецепты'],
    createdAt: '2026-10-11T10:00:00.000Z',
    updatedAt: '2026-10-12T18:04:00.000Z',
  },
];

const TAGS: TagCount[] = [
  { name: 'работа', count: 1 },
  { name: 'рецепты', count: 1 },
];

/** Мини-«сервер»: auth/me, заметки (GET/POST/PATCH/DELETE, q/tag), теги. */
function makeServer(initial: Note[] = NOTES, tagList: TagCount[] = TAGS): FetchHandler {
  let notes = [...initial];
  let nextId = Math.max(0, ...notes.map((note) => note.id)) + 1;

  return (url, init) => {
    const method = init.method ?? 'GET';

    if (url.endsWith('/api/auth/me')) return json(200, ME);
    if (url.endsWith('/api/tags')) return json(200, { items: tagList });

    const byId = url.match(/^\/api\/notes\/(\d+)$/);
    if (byId) {
      const id = Number(byId[1]);
      const index = notes.findIndex((note) => note.id === id);
      if (index === -1) {
        return json(404, { error: { code: 'NOT_FOUND', message: 'Заметка не найдена' } });
      }
      if (method === 'DELETE') {
        notes = notes.filter((note) => note.id !== id);
        return noContent(204);
      }
      if (method === 'PATCH') {
        const patch = JSON.parse(String(init.body)) as Partial<Note>;
        notes[index] = { ...notes[index], ...patch, updatedAt: '2026-10-13T10:00:00.000Z' };
        return json(200, notes[index]);
      }
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
      const params = new URL(`http://localhost${url}`).searchParams;
      const q = (params.get('q') ?? '').toLowerCase();
      const tag = params.get('tag');
      let items = notes;
      if (q) {
        items = items.filter((note) =>
          `${note.title ?? ''}\n${note.bodyMarkdown}`.toLowerCase().includes(q),
        );
      }
      if (tag) items = items.filter((note) => note.tags.includes(tag));
      return json(200, { items, total: items.length });
    }

    throw new Error(`Неожиданный запрос: ${method} ${url}`);
  };
}

/** Только восстановление сессии (для экранов авторизации). */
function authOnly(onLogin?: FetchHandler): FetchHandler {
  return (url, init) => {
    if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
    if (onLogin) return onLogin(url, init);
    throw new Error(`Неожиданный запрос: ${init.method ?? 'GET'} ${url}`);
  };
}

function renderApp(entries: Entry[] = ['/notes']) {
  return render(
    <MemoryRouter initialEntries={entries as never}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </MemoryRouter>,
  );
}

async function findList() {
  return screen.findByRole('list', { name: 'Список заметок' });
}

/** Все декоративные иконки должны быть скрыты от скринридера (DESIGN §5.2). */
function expectIconsHidden(root: ParentNode = document) {
  root.querySelectorAll('svg').forEach((svg) => {
    expect(svg).toHaveAttribute('aria-hidden', 'true');
    expect(svg).toHaveAttribute('focusable', 'false');
  });
}

/** Описатель текущего фокуса — для проверки tab-обхода. */
function activeLabel(): string {
  const el = document.activeElement as HTMLElement | null;
  if (!el || el === document.body) return 'body';
  const name =
    el.getAttribute('aria-label') ??
    el.getAttribute('placeholder') ??
    el.textContent?.trim().slice(0, 40) ??
    '';
  return `${el.tagName.toLowerCase()}:${name}${el.id ? `#${el.id}` : ''}`;
}

function tabThrough(user: ReturnType<typeof userEvent.setup>, times: number): Promise<string[]> {
  const seen: string[] = [];
  let chain = Promise.resolve();
  for (let i = 0; i < times; i += 1) {
    chain = chain.then(async () => {
      await user.tab();
      seen.push(activeLabel());
    });
  }
  return chain.then(() => seen);
}

beforeEach(() => {
  window.localStorage.clear();
});

/* =========================== Login / Register (S1/S2) ======================= */

describe('a11y: формы авторизации', () => {
  it('один h1, skip-link первым в tab-порядке и ведёт к форме (DESIGN §5.4)', async () => {
    setupFetch(authOnly());
    const user = userEvent.setup();
    renderApp(['/login']);

    await screen.findByRole('heading', { name: 'Вход' });
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);

    const skip = document.querySelector('a.skip-link') as HTMLAnchorElement;
    expect(skip).not.toBeNull();
    expect(skip.getAttribute('href')).toBe('#login-form');
    expect(document.querySelector('#login-form')).not.toBeNull();

    document.body.focus();
    await user.tab();
    expect(document.activeElement).toBe(skip);
    expectIconsHidden();
  });

  it('ошибки полей: aria-invalid + aria-describedby + role=alert, фокус на первом (NFR-19)', async () => {
    setupFetch(authOnly());
    const user = userEvent.setup();
    renderApp(['/login']);

    await screen.findByRole('heading', { name: 'Вход' });
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    const email = screen.getByLabelText(/Email/);
    expect(email).toHaveAttribute('aria-invalid', 'true');
    const describedBy = email.getAttribute('aria-describedby');
    expect(describedBy).toBeTruthy();
    const message = document.getElementById(describedBy as string);
    expect(message).not.toBeNull();
    expect(message).toHaveAttribute('role', 'alert');
    expect(message).toHaveTextContent('Укажите email.');
    expect(email).toHaveFocus();

    const password = screen.getByLabelText(/Пароль/);
    expect(password).toHaveAttribute('aria-invalid', 'true');
    const passwordMessage = document.getElementById(
      password.getAttribute('aria-describedby') as string,
    );
    expect(passwordMessage).toHaveAttribute('role', 'alert');
  });

  it('общая ошибка входа — role=alert с фокусом на алерте (DESIGN §2.11)', async () => {
    setupFetch(
      authOnly((url) => {
        if (url.endsWith('/api/auth/login')) {
          return json(401, { error: { code: 'UNAUTHORIZED', message: 'Неверные учётные данные' } });
        }
        throw new Error(`Неожиданный запрос: ${url}`);
      }),
    );
    const user = userEvent.setup();
    renderApp(['/login']);

    await screen.findByRole('heading', { name: 'Вход' });
    await user.type(screen.getByLabelText(/Email/), 'user@example.com');
    await user.type(screen.getByLabelText(/Пароль/), 'Secret12345');
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Неверные учётные данные');
    expect(alert).toHaveAttribute('aria-live', 'assertive');
    expect(alert).toHaveFocus();
  });

  it('регистрация: один h1, сила пароля не только цветом, ошибка подтверждения связана с полем', async () => {
    setupFetch(authOnly());
    const user = userEvent.setup();
    renderApp(['/register']);

    await screen.findByRole('heading', { name: 'Регистрация' });
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);

    await user.type(screen.getByLabelText(/Email/), 'new@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'abc');
    // Оценка дублируется текстом (не только цветом/шкалой), шкала скрыта.
    expect(screen.getByText(/Слабый пароль/)).toBeInTheDocument();
    expect(document.querySelector('.pw-meter')).toHaveAttribute('aria-hidden', 'true');

    await user.clear(screen.getByLabelText(/^Пароль/));
    await user.type(screen.getByLabelText(/^Пароль/), 'Secret12345');
    await user.type(screen.getByLabelText(/Повторите пароль/), 'Secret123');
    await user.click(screen.getByRole('button', { name: 'Создать аккаунт' }));

    const confirm = screen.getByLabelText(/Повторите пароль/);
    expect(confirm).toHaveAttribute('aria-invalid', 'true');
    const describedBy = document.getElementById(
      confirm.getAttribute('aria-describedby') as string,
    );
    expect(describedBy).toHaveAttribute('role', 'alert');
    expect(describedBy).toHaveTextContent('Пароли не совпадают.');
    expect(confirm).toHaveFocus();
  });
});

/* =============================== Notes (S3) ================================ */

describe('a11y: список заметок', () => {
  it('переключатель вида: role=group + aria-label, aria-pressed, скрытый role=status (NFR-16)', async () => {
    setupFetch(makeServer());
    renderApp(['/notes']);
    await findList();

    const group = screen.getByRole('group', { name: 'Вид отображения заметок' });
    const grid = within(group).getByRole('button', { name: 'Плитки' });
    const list = within(group).getByRole('button', { name: 'Список' });
    expect(grid).toHaveAttribute('aria-pressed', 'true');
    expect(list).toHaveAttribute('aria-pressed', 'false');

    const status = document.querySelector('[data-view-status]') as HTMLElement;
    expect(status).toHaveAttribute('role', 'status');
    expect(status).toHaveTextContent('Текущий вид: плитки');
  });

  it('поиск: sr-only label связан с полем, aria-describedby указывает на живой регион (NFR-16)', async () => {
    // Список «висит» — регион результатов обязан существовать и в состоянии загрузки.
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(200, ME);
      if (url.endsWith('/api/tags')) return json(200, { items: TAGS });
      return new Promise<Response>(() => {
        /* загрузка не завершается */
      });
    });
    renderApp(['/notes']);

    await screen.findByText('Загрузка заметок…');
    const input = screen.getByLabelText('Поиск по заметкам');
    expect(input).toHaveAttribute('type', 'search');
    expect(input).toHaveAttribute('autocomplete', 'off');

    const describedBy = input.getAttribute('aria-describedby');
    expect(describedBy).toBeTruthy();
    const region = document.getElementById(describedBy as string);
    expect(region).not.toBeNull();
    expect(region).toHaveAttribute('role', 'status');
    expect(region).toHaveAttribute('aria-live', 'polite');

    const label = document.querySelector('label[for="q"]') as HTMLLabelElement;
    expect(label).toHaveClass('sr-only');
    expect(label).toHaveTextContent('Поиск по заметкам');
  });

  it('чипы тегов: role=group с подписью, кнопки aria-pressed, счётчик aria-hidden (NFR-16)', async () => {
    setupFetch(makeServer());
    renderApp(['/notes']);
    await findList();

    const group = screen.getByRole('group', { name: 'Фильтр по тегу:' });
    const chip = within(group).getByRole('button', { name: 'работа' });
    expect(chip).toHaveAttribute('aria-pressed', 'false');
    const count = chip.querySelector('.chip__count') as HTMLElement;
    expect(count).toHaveAttribute('aria-hidden', 'true');
    expect(count).toHaveTextContent('1');
    // Статичная подпись состояния фильтра — не live-регион (DESIGN §2.6).
    const filterCount = document.querySelector('[data-filter-count]') as HTMLElement;
    expect(filterCount).not.toHaveAttribute('role');
    expect(filterCount).not.toHaveAttribute('aria-live');
  });

  it('кнопки-иконки заметки имеют контекстный aria-label (NFR-17)', async () => {
    setupFetch(makeServer());
    renderApp(['/notes']);
    await findList();

    expect(
      screen.getByRole('link', { name: 'Редактировать заметку «План на неделю»' }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Удалить заметку «План на неделю»' }),
    ).toBeInTheDocument();
    expectIconsHidden();
  });

  it('результаты и empty-state объявляются (role=status) (NFR-20)', async () => {
    setupFetch(makeServer([], []));
    renderApp(['/notes']);

    await screen.findByText('Пока ни одной заметки');
    const block = document.querySelector('[data-empty-nonotes]') as HTMLElement;
    expect(block).not.toBeNull();
    const region = document.querySelector('#result-status') as HTMLElement;
    expect(region).toHaveAttribute('role', 'status');
    expect(region).toHaveTextContent('0 заметок');
    expect(within(block).getByRole('link', { name: 'Создать заметку' })).toBeInTheDocument();
  });

  it('диалог удаления: aria-связи, autofocus на безопасном действии, Esc закрывает и возвращает фокус (NFR-15)', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes']);
    await findList();

    const trigger = screen.getByRole('button', { name: 'Удалить заметку «План на неделю»' });
    await user.click(trigger);

    const dialog = await screen.findByRole('dialog');
    const labelledBy = dialog.getAttribute('aria-labelledby');
    const describedBy = dialog.getAttribute('aria-describedby');
    expect(document.getElementById(labelledBy as string)).toHaveTextContent('Удалить заметку?');
    expect(document.getElementById(describedBy as string)).toHaveTextContent('План на неделю');

    const cancel = within(dialog).getByRole('button', { name: 'Отмена' });
    await waitFor(() => expect(cancel).toHaveFocus());
    // Фокус не «уходит» за модальное окно.
    expect(dialog.contains(document.activeElement)).toBe(true);

    await user.keyboard('{Escape}');

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(trigger).toHaveFocus();
    expect(screen.getByText('План на неделю')).toBeInTheDocument();
  });

  it(
    'Tab обходит весь экран без «залипания» и циклически (NFR-15)',
    async () => {
      setupFetch(makeServer());
      const user = userEvent.setup();
      renderApp(['/notes']);
      await findList();

      document.body.focus();
      const seen = await tabThrough(user, 60);

      // Ни один элемент не получает фокус дважды подряд.
      for (let i = 1; i < seen.length; i += 1) {
        expect(seen[i], `повтор фокуса на шаге ${i}`).not.toBe(seen[i - 1]);
      }

      // Ключевые элементы достижимы с клавиатуры.
      const flat = seen.join(' | ');
      expect(flat).toContain('Перейти к заметкам');
      expect(flat).toContain('Выйти');
      expect(flat).toContain('Создать заметку');
      expect(flat).toContain('Плитки');
      expect(flat).toContain('Список');
      expect(flat).toContain('#q');
      expect(flat).toContain('Редактировать заметку «План на неделю»');
      expect(flat).toContain('Удалить заметку «План на неделю»');

      // Обход цикличен: последовательность повторяется с найденным периодом.
      const firstRepeat = seen.indexOf(seen[0], 1);
      expect(firstRepeat).toBeGreaterThan(1);
      for (let i = 0; i < firstRepeat && i + firstRepeat < seen.length; i += 1) {
        expect(seen[i]).toBe(seen[i + firstRepeat]);
      }
    },
    30_000,
  );
});

/* =============================== Editor (S4) =============================== */

describe('a11y: редактор', () => {
  it('один h1, toolbar/группы/разделители и aria-label у кнопок (DESIGN §2.7/§5.2)', async () => {
    setupFetch(makeServer());
    renderApp(['/notes/new']);
    await screen.findByRole('heading', { name: 'Новая заметка' });

    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);

    const toolbar = screen.getByRole('toolbar', { name: 'Форматирование markdown' });
    const describedBy = toolbar.getAttribute('aria-describedby');
    expect(document.getElementById(describedBy as string)).not.toBeNull();

    expect(within(toolbar).getAllByRole('group')).toHaveLength(4);
    expect(within(toolbar).getAllByRole('separator')).toHaveLength(3);

    const buttons = within(toolbar).getAllByRole('button');
    expect(buttons.length).toBeGreaterThanOrEqual(10);
    buttons.forEach((button) => {
      expect(button).toHaveAttribute('aria-label');
      expect(button).toHaveAttribute('title');
      expect(button.getAttribute('tabindex')).not.toBe('-1');
    });
    expectIconsHidden();
  });

  it('табы «Редактор/Просмотр»: tablist/tab/tabpanel, roving tabindex, Arrow (NFR-23)', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes/new']);
    await screen.findByRole('heading', { name: 'Новая заметка' });

    const tablist = screen.getByRole('tablist', { name: 'Редактор или просмотр' });
    const tabs = within(tablist).getAllByRole('tab');
    expect(tabs).toHaveLength(2);
    expect(tabs[0]).toHaveAttribute('aria-selected', 'true');
    expect(tabs[0]).toHaveAttribute('tabindex', '0');
    expect(tabs[1]).toHaveAttribute('tabindex', '-1');

    // Каждый таб указывает на существующую панель и наоборот (aria-связь двусторонняя).
    tabs.forEach((tab) => {
      if (tab.getAttribute('aria-selected') === 'true') expect(tab).toHaveAttribute('tabindex', '0');
      else expect(tab).toHaveAttribute('tabindex', '-1');
      const panel = document.getElementById(tab.getAttribute('aria-controls') as string);
      expect(panel).toHaveAttribute('role', 'tabpanel');
      expect(panel).toHaveAttribute('aria-labelledby', tab.id);
    });

    tabs[0].focus();
    await user.keyboard('{ArrowRight}');
    expect(tabs[1]).toHaveFocus();
    expect(tabs[1]).toHaveAttribute('aria-selected', 'true');
    expect(tabs[0]).toHaveAttribute('tabindex', '-1');

    await user.keyboard('{ArrowLeft}');
    expect(tabs[0]).toHaveFocus();
    expect(tabs[0]).toHaveAttribute('aria-selected', 'true');
  });

  it('поле markdown подписано, поле тегов связано с хинтом, ошибка лимита — role=alert + aria-invalid', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes/new']);
    await screen.findByRole('heading', { name: 'Новая заметка' });

    const markdown = screen.getByLabelText('Текст заметки в markdown');
    expect(markdown).toHaveAttribute('maxlength', '100000');
    expect(document.getElementById(markdown.getAttribute('aria-describedby') as string)).not.toBeNull();

    const tags = screen.getByLabelText('Теги');
    expect(document.getElementById(tags.getAttribute('aria-describedby') as string)).not.toBeNull();

    // Тег длиннее 50 символов → сообщение связано с полем.
    await user.type(tags, 'я'.repeat(51));
    await user.keyboard('{Enter}');
    const error = await screen.findByRole('alert');
    expect(error).toHaveTextContent('Тег длиннее 50 символов');
    expect(tags).toHaveAttribute('aria-invalid', 'true');
    expect(tags.getAttribute('aria-describedby')).toContain(error.id);
  });

  it('пустая заметка → role=alert «Заметка пустая», статус сохранения — role=status', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes/new']);
    await screen.findByRole('heading', { name: 'Новая заметка' });

    await user.click(screen.getByRole('button', { name: 'Сохранить' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Заметка пустая');

    await user.type(screen.getByLabelText('Текст заметки в markdown'), 'текст');
    const dirty = document.querySelector('[data-dirty-state]') as HTMLElement;
    expect(dirty).toHaveAttribute('role', 'status');
    expect(dirty).toHaveAttribute('aria-live', 'polite');
  });

  it('диалог несохранённых правок: aria-связи, Esc = «остаться», возврат фокуса (NFR-15)', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes/new']);
    await screen.findByRole('heading', { name: 'Новая заметка' });

    await user.type(screen.getByLabelText('Текст заметки в markdown'), 'черновик');
    const cancel = screen.getByRole('button', { name: 'Отмена' });
    await user.click(cancel);

    const dialog = await screen.findByRole('dialog');
    expect(
      document.getElementById(dialog.getAttribute('aria-labelledby') as string),
    ).toHaveTextContent('Есть несохранённые изменения');
    expect(
      within(dialog).getByRole('button', { name: 'Остаться в редакторе' }),
    ).toHaveFocus();

    await user.keyboard('{Escape}');

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(cancel).toHaveFocus();
    // Остались в редакторе, черновик на месте.
    expect(screen.getByRole('heading', { name: 'Новая заметка' })).toBeInTheDocument();
    expect(screen.getByLabelText('Текст заметки в markdown')).toHaveValue('черновик');
  });
});

/* =============================== Note (S5) ================================ */

describe('a11y: просмотр заметки', () => {
  it('один h1, теги — группа текста, диалог удаления возвращает фокус (DESIGN §5.4)', async () => {
    setupFetch(makeServer());
    const user = userEvent.setup();
    renderApp(['/notes/1']);

    await screen.findByRole('heading', { level: 1, name: 'План на неделю' });
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
    expect(screen.getByRole('group', { name: 'Теги заметки' })).toHaveTextContent('работа');

    const trigger = screen.getByRole('button', { name: 'Удалить' });
    await user.click(trigger);
    await screen.findByRole('dialog');
    await user.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(trigger).toHaveFocus();
    expect(screen.getByRole('heading', { level: 1 })).toBeInTheDocument();
  });

  it('состояние «Заметка не найдена» — экран с одним h1 и ссылкой (NFR-20)', async () => {
    setupFetch(makeServer());
    renderApp(['/notes/999']);

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Заметка не найдена' }),
    ).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 1 })).toHaveLength(1);
    expect(screen.getByRole('link', { name: 'К моим заметкам' })).toBeInTheDocument();
  });

  it('состояние ошибки загрузки — заголовок + role=alert и «Повторить»', async () => {
    setupFetch((url, init) => {
      if (url.endsWith('/api/auth/me')) return json(200, ME);
      if (url.match(/^\/api\/notes\/\d+$/) && (init.method ?? 'GET') === 'GET') {
        return json(500, { error: { code: 'INTERNAL', message: 'Сбой' } });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });
    renderApp(['/notes/1']);

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Не удалось загрузить заметку' }),
    ).toBeInTheDocument();
    expect(screen.getByRole('alert')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Повторить' })).toBeInTheDocument();
  });

  it('порядок заголовков в статье не пропускает уровней (h1 страницы → h2 статьи)', async () => {
    // Заметка начинается с `##` — минимальный уровень должен стать h2, а не h3.
    const note: Note = {
      ...NOTES[0],
      id: 42,
      title: 'Заметка без «#»',
      bodyMarkdown: '## Первый подраздел\n\nтекст\n\n### Вложенный\n\n#### Глубокий\n\n##### Ещё глубже',
    };
    setupFetch(makeServer([note]));
    renderApp(['/notes/42']);

    await screen.findByRole('heading', { level: 1, name: 'Заметка без «#»' });
    const article = document.querySelector('article.md') as HTMLElement;
    const levels = [...article.querySelectorAll('h1, h2, h3, h4, h5, h6')].map((h) =>
      Number(h.tagName.slice(1)),
    );
    expect(levels[0]).toBe(2);
    // Уровни идут без «дыр» и не выходят за allowlist (h2–h4).
    expect(levels.every((level) => level <= 4)).toBe(true);
    levels.forEach((level, index) => {
      if (index > 0) expect(level - levels[index - 1]).toBeLessThanOrEqual(1);
    });
  });
});
