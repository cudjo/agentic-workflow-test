/**
 * pages/Notes.tsx — экран `S3` «Мои заметки».
 *
 * T-06 реализует только фундамент + auth-экраны. Полный список (плитки/список,
 * поиск, фильтры, удаление, состояния) — задача T-08; здесь — минимальный
 * каркас страницы, достаточный для целевого редиректа после входа/регистрации.
 */
export default function Notes() {
  return (
    <section aria-labelledby="notes-title">
      <div className="page__head">
        <div>
          <h1 id="notes-title" style={{ marginBottom: 'var(--sp-1)' }}>
            Мои заметки
          </h1>
          <p className="muted small">Сортировка: сначала обновлённые</p>
        </div>
      </div>

      <div className="empty">
        <div className="empty__art" aria-hidden="true">
          <svg
            aria-hidden="true"
            focusable="false"
            width="30"
            height="30"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
          >
            <path d="M4 4h11l5 5v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z" />
            <path d="M14 4v6h6" />
          </svg>
        </div>
        <p className="empty__title">Пока ни одной заметки</p>
        <p className="empty__text">
          Создайте первую заметку — markdown, теги и поиск подождут вас внутри.
        </p>
      </div>
    </section>
  );
}
