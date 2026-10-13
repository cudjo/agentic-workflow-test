/** pages/NotFound.tsx — fallback для неизвестных маршрутов. */
import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <main className="container page">
      <h1 style={{ marginBottom: 'var(--sp-3)' }}>Страница не найдена</h1>
      <p className="muted" style={{ marginBottom: 'var(--sp-5)' }}>
        Такой страницы не существует или она была перемещена.
      </p>
      <Link className="btn btn--primary" to="/notes">
        К моим заметкам
      </Link>
    </main>
  );
}
