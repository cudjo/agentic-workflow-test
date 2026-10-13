/**
 * components/NoteItem.tsx — заметка: карточка (плитка) и строка (список).
 *
 * Один и тот же DOM на оба вида (AC-24/AC-26): раскладку переключает контейнер
 * `.results--grid` / `.results--list`, поэтому состав и порядок не меняются.
 * Заголовок (`clamp-2`; для пустого — первая строка текста), фрагмент
 * (`clamp-3`, plain-text без рендера markdown), теги (текст), дата и действия
 * «Редактировать»/«Удалить», всегда видимые, с контекстными `aria-label`.
 */
import { Link } from 'react-router-dom';
import type { Note } from '../api/notes';
import { formatNoteDate } from '../lib/format';
import { noteTitle, toPlainText } from '../lib/note-text';
import { PencilIcon, TrashIcon } from './icons';

interface NoteItemProps {
  note: Note;
  onDelete: () => void;
}

export function NoteItem({ note, onDelete }: NoteItemProps) {
  const title = noteTitle(note);
  const snippet = toPlainText(note.bodyMarkdown);

  return (
    <li className="note-item" data-note>
      <div className="note-item__row">
        <div className="note-item__main">
          <h3 className="note-item__title clamp-2">
            <Link to={`/notes/${note.id}`}>{title}</Link>
          </h3>
          {snippet ? <p className="note-item__snippet clamp-3">{snippet}</p> : null}
        </div>
        <div className="note-item__side">
          <div className="note-item__tags">
            {note.tags.length > 0 ? (
              note.tags.map((tag) => (
                <span className="tag" key={tag}>
                  <span className="tag__label">{tag}</span>
                </span>
              ))
            ) : (
              <span className="tiny dim">Без тегов</span>
            )}
          </div>
          <time className="note-item__date" dateTime={note.updatedAt}>
            {formatNoteDate(note.updatedAt)}
          </time>
        </div>
      </div>
      <div className="note-item__actions">
        <Link
          className="btn btn--ghost btn--icon btn--sm"
          to={`/notes/${note.id}/edit`}
          aria-label={`Редактировать заметку «${title}»`}
        >
          <PencilIcon size={16} />
        </Link>
        <button
          className="btn btn--ghost btn--icon btn--sm"
          type="button"
          aria-label={`Удалить заметку «${title}»`}
          onClick={onDelete}
        >
          <TrashIcon size={16} />
        </button>
      </div>
    </li>
  );
}
