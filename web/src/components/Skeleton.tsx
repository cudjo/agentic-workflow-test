/**
 * components/Skeleton.tsx — скелетоны загрузки списка (DESIGN §2.10/§4.2.1).
 *
 * Форма повторяет будущую раскладку (3 плитки в `results--grid`): заголовок,
 * строки текста, чипы и «дата». Контейнер `aria-hidden`, состояние объявляется
 * скрытым `role="status"` «Загрузка заметок…» — спиннеров на весь экран нет.
 */
export function NoteListSkeleton() {
  return (
    <div data-results-wrap>
      <p className="sr-only" role="status">
        Загрузка заметок…
      </p>
      <ul className="results results--grid" aria-hidden="true">
        {[0, 1, 2].map((index) => (
          <li className="note-item" key={index}>
            <div className="note-item__row">
              <div className="note-item__main stack">
                <span
                  className="skeleton skeleton--title"
                  style={index === 1 ? { width: '45%' } : index === 2 ? { width: '70%' } : undefined}
                />
                <span className="skeleton skeleton--line" />
                <span
                  className="skeleton skeleton--line"
                  style={{ width: index === 1 ? '72%' : '88%' }}
                />
                {index !== 1 ? (
                  <span className="skeleton skeleton--line" style={{ width: '64%' }} />
                ) : null}
              </div>
              <div className="note-item__side stack">
                <div className="row">
                  <span className="skeleton skeleton--chip" />
                  {index !== 1 ? <span className="skeleton skeleton--chip" /> : null}
                </div>
                <span className="skeleton skeleton--line" style={{ width: '80px' }} />
              </div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
