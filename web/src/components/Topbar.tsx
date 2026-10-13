/**
 * components/Topbar.tsx — верхняя навигация с userchip и кнопкой «Выйти»
 * (DESIGN §1.1, §2.13). «Выйти» инвалидирует сессию на сервере
 * (`POST /api/auth/logout`) и возвращает на `/login` (DESIGN §1.2 поток F).
 */
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';

export function Topbar() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);

  async function handleLogout(): Promise<void> {
    setBusy(true);
    try {
      await logout();
    } finally {
      setBusy(false);
      navigate('/login', { replace: true });
    }
  }

  const initial = user?.email ? user.email[0]!.toUpperCase() : '?';

  return (
    <header className="topbar">
      <div className="topbar__inner">
        <Link className="brand" to="/notes">
          <span className="brand__mark" aria-hidden="true">
            З
          </span>
          Заметки
        </Link>
        <span className="topbar__spacer" />
        {user ? (
          <div className="userchip">
            <span className="avatar" aria-hidden="true">
              {initial}
            </span>
            <span className="userchip__name">{user.email}</span>
            <button
              type="button"
              className="btn btn--sm btn--ghost"
              onClick={handleLogout}
              disabled={busy}
            >
              {busy ? 'Выхожу…' : 'Выйти'}
            </button>
          </div>
        ) : null}
      </div>
    </header>
  );
}
