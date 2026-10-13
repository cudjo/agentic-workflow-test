/**
 * auth.test.tsx — ключевые сценарии T-06: guard маршрутов и auth-экраны
 * (AC-1, AC-2, AC-4, AC-5, AC-6, AC-10, поток F).
 *
 * `fetch` мокается целиком; каждый тест описывает нужные ответы сервера.
 */
import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import App from '../App';
import { AuthProvider } from '../auth/AuthContext';

type RouteHandler = (url: string, init: RequestInit) => Response | Promise<Response>;
type Entry = string | { pathname: string; state?: unknown };

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

let fetchMock: ReturnType<typeof vi.fn>;

function setupFetch(handler: RouteHandler): void {
  fetchMock = vi.fn(async (input: unknown, init?: RequestInit) => {
    const url =
      typeof input === 'string' ? input : String((input as { url?: string })?.url ?? input);
    return handler(url, init ?? {});
  });
  vi.stubGlobal('fetch', fetchMock);
}

function renderApp(entries: Entry[]) {
  return render(
    <MemoryRouter initialEntries={entries as never}>
      <AuthProvider>
        <App />
      </AuthProvider>
    </MemoryRouter>,
  );
}

const UNAUTHORIZED = { error: { code: 'UNAUTHORIZED', message: 'Требуется авторизация' } };

describe('guard маршрутов', () => {
  it('перенаправляет неавторизованного с /notes на /login и не показывает заметки', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    renderApp(['/notes']);

    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Мои заметки' })).not.toBeInTheDocument();
  });

  it('после входа возвращает на запрошенный URL (сохранённый guard-ом)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/login')) {
        return json(200, { user: { id: 1, email: 'user@example.com' } });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/notes']);

    await screen.findByRole('heading', { name: 'Вход' });
    await user.type(screen.getByLabelText(/^Email/), 'user@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'Secret12345');
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    expect(await screen.findByRole('heading', { name: 'Мои заметки' })).toBeInTheDocument();
  });
});

describe('вход', () => {
  it('успешный вход ведёт на /notes и показывает email в topbar (AC-4)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/login')) {
        return json(200, { user: { id: 7, email: 'user@example.com' } });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/login']);
    await screen.findByRole('heading', { name: 'Вход' });

    await user.type(screen.getByLabelText(/^Email/), 'user@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'Secret12345');
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    expect(await screen.findByRole('heading', { name: 'Мои заметки' })).toBeInTheDocument();
    expect(screen.getByText('user@example.com')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Выйти' })).toBeInTheDocument();
  });

  it('неверные данные показывают обобщённую ошибку (AC-5)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/login')) {
        return json(401, { error: { code: 'UNAUTHORIZED', message: 'Неверные учётные данные' } });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/login']);
    await screen.findByRole('heading', { name: 'Вход' });

    await user.type(screen.getByLabelText(/^Email/), 'user@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'wrongpassword');
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Неверные учётные данные');
    expect(screen.queryByRole('heading', { name: 'Мои заметки' })).not.toBeInTheDocument();
  });

  it('rate-limit (429) показывает баннер с таймером и блокирует форму (AC-6)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/login')) {
        return json(
          429,
          { error: { code: 'RATE_LIMITED', message: 'Слишком много попыток' } },
          { 'retry-after': '900' },
        );
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/login']);
    await screen.findByRole('heading', { name: 'Вход' });

    await user.type(screen.getByLabelText(/^Email/), 'user@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'wrongpassword');
    await user.click(screen.getByRole('button', { name: 'Войти' }));

    expect(await screen.findByText('Слишком много попыток входа')).toBeInTheDocument();
    expect(screen.getByText(/Повторите через 15:00/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Войти' })).toBeDisabled();
    expect(screen.getByLabelText(/^Email/)).toBeDisabled();
  });
});

describe('регистрация', () => {
  it('успешная регистрация ведёт на /notes (AC-1)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/register')) {
        return json(201, { user: { id: 3, email: 'new@example.com' } });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/register']);
    await screen.findByRole('heading', { name: 'Регистрация' });

    await user.type(screen.getByLabelText(/^Email/), 'new@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'Secret12345');
    await user.type(screen.getByLabelText(/^Повторите пароль/), 'Secret12345');
    await user.click(screen.getByRole('button', { name: 'Создать аккаунт' }));

    expect(await screen.findByRole('heading', { name: 'Мои заметки' })).toBeInTheDocument();
  });

  it('дубликат email показывает «Этот email уже зарегистрирован» (AC-2)', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      if (url.endsWith('/api/auth/register')) {
        return json(409, {
          error: { code: 'CONFLICT', message: 'Этот email уже зарегистрирован', field: 'email' },
        });
      }
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/register']);
    await screen.findByRole('heading', { name: 'Регистрация' });

    await user.type(screen.getByLabelText(/^Email/), 'taken@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), 'Secret12345');
    await user.type(screen.getByLabelText(/^Повторите пароль/), 'Secret12345');
    await user.click(screen.getByRole('button', { name: 'Создать аккаунт' }));

    expect(await screen.findByText('Этот email уже зарегистрирован')).toBeInTheDocument();
    expect(screen.getByText('Уже используется.')).toBeInTheDocument();
  });

  it('клиентская валидация не отправляет запрос при коротком пароле и несовпадении', async () => {
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(401, UNAUTHORIZED);
      throw new Error(`Запрос не должен был уйти: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/register']);
    await screen.findByRole('heading', { name: 'Регистрация' });

    await user.type(screen.getByLabelText(/^Email/), 'new@example.com');
    await user.type(screen.getByLabelText(/^Пароль/), '1234');
    await user.type(screen.getByLabelText(/^Повторите пароль/), '12345');
    await user.click(screen.getByRole('button', { name: 'Создать аккаунт' }));

    expect(await screen.findByText('Слишком короткий пароль: нужно минимум 8 символов.')).toBeInTheDocument();
    expect(screen.getByText('Пароли не совпадают.')).toBeInTheDocument();
    expect(
      fetchMock.mock.calls.some(([url]) => String(url).includes('/api/auth/register')),
    ).toBe(false);
  });
});

describe('выход', () => {
  it('«Выйти» вызывает logout с CSRF-заголовком и ведёт на /login (поток F)', async () => {
    document.cookie = 'XSRF-TOKEN=csrf-token-123';
    setupFetch((url) => {
      if (url.endsWith('/api/auth/me')) return json(200, { user: { id: 1, email: 'user@example.com' } });
      if (url.endsWith('/api/auth/logout')) return noContent(204);
      throw new Error(`Неожиданный запрос: ${url}`);
    });

    const user = userEvent.setup();
    renderApp(['/notes']);

    await screen.findByRole('heading', { name: 'Мои заметки' });
    await user.click(screen.getByRole('button', { name: 'Выйти' }));

    expect(await screen.findByRole('heading', { name: 'Вход' })).toBeInTheDocument();

    const logoutCall = fetchMock.mock.calls.find(([url]) => String(url).endsWith('/api/auth/logout'));
    expect(logoutCall).toBeTruthy();
    const init = logoutCall?.[1] as RequestInit;
    expect((init.headers as Record<string, string>)['X-CSRF-Token']).toBe('csrf-token-123');
  });
});
