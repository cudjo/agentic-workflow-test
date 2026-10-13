/**
 * auth/AuthContext.tsx — состояние сессии и операции входа/регистрации/выхода.
 *
 *   * при монтировании восстанавливает сессию через `GET /api/auth/me` (AC-9);
 *   * на 401 в произвольном запросе приложение возвращается на `/login`
 *     с сохранением целевого URL (`reason: 'expired'` — DESIGN §1.2 поток B).
 */
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { authApi, setUnauthorizedHandler, type User } from '../api/client';

export type AuthStatus = 'loading' | 'authenticated' | 'anonymous';

export interface AuthContextValue {
  user: User | null;
  status: AuthStatus;
  login(email: string, password: string): Promise<User>;
  register(email: string, password: string): Promise<User>;
  logout(): Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [status, setStatus] = useState<AuthStatus>('loading');
  const navigate = useNavigate();
  const location = useLocation();

  // Актуальный location для колбэка 401 — обновляем без переподписки.
  const locationRef = useRef(location);
  locationRef.current = location;

  // Восстановление сессии при загрузке приложения.
  useEffect(() => {
    let active = true;
    authApi
      .me()
      .then(({ user: me }) => {
        if (!active) return;
        setUser(me);
        setStatus('authenticated');
      })
      .catch(() => {
        if (!active) return;
        setUser(null);
        setStatus('anonymous');
      });
    return () => {
      active = false;
    };
  }, []);

  // Глобальная обработка 401 (кроме `/me`): редирект на вход с сохранением URL.
  useEffect(() => {
    setUnauthorizedHandler(() => {
      setUser(null);
      setStatus('anonymous');
      const current = locationRef.current;
      const from = `${current.pathname}${current.search}`;
      if (current.pathname !== '/login') {
        navigate('/login', { replace: true, state: { from, reason: 'expired' } });
      }
    });
    return () => setUnauthorizedHandler(null);
  }, [navigate]);

  const login = useCallback(async (email: string, password: string): Promise<User> => {
    const { user: loggedIn } = await authApi.login(email, password);
    setUser(loggedIn);
    setStatus('authenticated');
    return loggedIn;
  }, []);

  const register = useCallback(async (email: string, password: string): Promise<User> => {
    const { user: created } = await authApi.register(email, password);
    setUser(created);
    setStatus('authenticated');
    return created;
  }, []);

  const logout = useCallback(async (): Promise<void> => {
    try {
      await authApi.logout();
    } finally {
      setUser(null);
      setStatus('anonymous');
    }
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({ user, status, login, register, logout }),
    [user, status, login, register, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth должен использоваться внутри <AuthProvider>');
  }
  return context;
}
