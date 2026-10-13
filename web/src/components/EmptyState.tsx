/**
 * components/EmptyState.tsx — два разных пустых состояния (DESIGN §2.9).
 *
 *   * `no-notes`   — заметок нет вообще и фильтры не активны → CTA «Создать заметку»;
 *   * `no-results` — пусто при активном поиске/теге → «Сбросить поиск и фильтры».
 *
 * Одновременно виден ровно один вариант (решает страница, §4.2.2).
 */
import { Link } from 'react-router-dom';
import { FileTextIcon, PlusIcon, RefreshIcon, SearchIcon } from './icons';

interface EmptyStateProps {
  variant: 'no-notes' | 'no-results';
  /** Целевой маршрут редактора (S4) для CTA «Создать заметку». */
  createHref?: string;
  onReset?: () => void;
}

export function EmptyState({ variant, createHref = '/notes/new', onReset }: EmptyStateProps) {
  if (variant === 'no-notes') {
    return (
      <div className="empty" data-empty-nonotes>
        <div className="empty__art" aria-hidden="true">
          <FileTextIcon size={30} />
        </div>
        <p className="empty__title">Пока ни одной заметки</p>
        <p className="empty__text">
          Создайте первую заметку — markdown, теги и поиск подождут вас внутри.
        </p>
        <Link className="btn btn--primary" to={createHref}>
          <PlusIcon size={16} />
          Создать заметку
        </Link>
      </div>
    );
  }

  return (
    <div className="empty" data-empty-noresults>
      <div className="empty__art" aria-hidden="true">
        <SearchIcon size={28} />
      </div>
      <p className="empty__title">Ничего не найдено</p>
      <p className="empty__text">
        Нет заметок, которые совпадают и с поиском, и с выбранным тегом. Попробуйте изменить
        запрос или снять фильтр.
      </p>
      <button className="btn btn--primary" type="button" onClick={onReset}>
        <RefreshIcon size={16} />
        Сбросить поиск и фильтры
      </button>
    </div>
  );
}
