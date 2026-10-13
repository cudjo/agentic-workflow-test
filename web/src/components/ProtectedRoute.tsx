/**
 * components/ProtectedRoute.tsx — guard защищённых маршрутов (DESIGN §1.2 поток G).
 *
 * Пока сессия восстанавливается (`loading`) — ничего защищённого не показываем.
 * Неавторизованный → редирект на `/login` с сохранением целевого URL; после
 * успешного входа пользователь возвращается на запрошенный экран (AC-10).
 */
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';

export function ProtectedRoute() {
  const { status } = useAuth();
  const location = useLocation();

  if (status === 'loading') {
    return (
      <p className="sr-only" role="status">
        Проверка сессии…
      </p>
    );
  }

  if (status === 'anonymous') {
    const from = `${location.pathname}${location.search}`;
    return <Navigate to="/login" replace state={{ from }} />;
  }

  return <Outlet />;
}
