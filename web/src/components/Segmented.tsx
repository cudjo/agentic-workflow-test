/**
 * components/Segmented.tsx — переключатель вида «плитки/список» (DESIGN §2.3).
 *
 * `role="group"` + кнопки `aria-pressed`; `ArrowLeft/ArrowRight` перемещают фокус
 * и выбирают вид; текущее состояние дублируется скрытым `role="status"`
 * «Текущий вид: …» (NFR-16). Один DOM списка — переключение меняет только
 * раскладку (AC-26), поэтому выбор сообщается наверх через `onChange`.
 */
import { useRef, type KeyboardEvent } from 'react';
import { GridIcon, ListIcon } from './icons';
import type { ViewMode } from '../lib/view';

interface SegmentedProps {
  value: ViewMode;
  onChange: (value: ViewMode) => void;
}

export function Segmented({ value, onChange }: SegmentedProps) {
  const gridRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLButtonElement>(null);

  function handleKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
    event.preventDefault();
    const next: ViewMode = value === 'grid' ? 'list' : 'grid';
    onChange(next);
    (next === 'grid' ? gridRef : listRef).current?.focus();
  }

  return (
    <>
      <div
        className="segmented"
        role="group"
        aria-label="Вид отображения заметок"
        data-view-toggle
      >
        <button
          ref={gridRef}
          type="button"
          className="segmented__btn"
          data-view-btn
          data-view="grid"
          aria-pressed={value === 'grid'}
          onClick={() => onChange('grid')}
          onKeyDown={handleKeyDown}
        >
          <GridIcon size={16} />
          Плитки
        </button>
        <button
          ref={listRef}
          type="button"
          className="segmented__btn"
          data-view-btn
          data-view="list"
          aria-pressed={value === 'list'}
          onClick={() => onChange('list')}
          onKeyDown={handleKeyDown}
        >
          <ListIcon size={16} />
          Список
        </button>
      </div>
      <span className="sr-only" role="status" data-view-status>
        Текущий вид: {value === 'grid' ? 'плитки' : 'список'}
      </span>
    </>
  );
}
