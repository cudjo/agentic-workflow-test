/**
 * components/TagFilter.tsx — чипы-фильтры по тегам (DESIGN §2.5/§2.6).
 *
 * Теги из `GET /api/tags` со счётчиками; чип — toggle-кнопка `aria-pressed`
 * (повторный клик снимает фильтр). Контейнер — `role="group"` с подписью.
 * Рядом — подпись состояния фильтров и «Сбросить» (обнуляет q и tag).
 */
import { RefreshIcon } from './icons';
import type { TagCount } from '../api/notes';

interface TagFilterProps {
  tags: TagCount[];
  /** Активный тег или `null`. */
  active: string | null;
  onToggle: (tag: string) => void;
  onReset: () => void;
  /** Активен ли поисковый запрос (для подписи «Активен поиск»). */
  hasQuery: boolean;
}

export function TagFilter({ tags, active, onToggle, onReset, hasQuery }: TagFilterProps) {
  const label = active
    ? `Активен фильтр: ${active}`
    : hasQuery
      ? 'Активен поиск'
      : 'Фильтры не применены';

  return (
    <div className="filterbar">
      <span className="small muted" id="filter-label">
        Фильтр по тегу:
      </span>
      <div className="row wrap" role="group" aria-labelledby="filter-label">
        {tags.map((tag) => (
          <button
            key={tag.name}
            type="button"
            className="chip"
            data-tag-chip={tag.name}
            aria-pressed={active === tag.name}
            onClick={() => onToggle(tag.name)}
          >
            {tag.name}
            <span className="chip__count" aria-hidden="true">
              {tag.count}
            </span>
          </button>
        ))}
      </div>
      <span className="topbar__spacer" />
      <span className="tiny dim" data-filter-count>
        {label}
      </span>
      <button
        className="btn btn--ghost btn--sm"
        type="button"
        data-reset-filters
        onClick={onReset}
      >
        <RefreshIcon size={14} />
        Сбросить
      </button>
    </div>
  );
}
