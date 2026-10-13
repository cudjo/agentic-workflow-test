/**
 * pages/Notes.tsx — экран `S3` «Мои заметки» (T-08).
 *
 * Полный список заметок: плитки/список на едином DOM (AC-24/AC-26), предпочтение
 * вида в `localStorage` (AC-25/AC-27), серверный поиск с debounce и чипы-фильтры
 * тегов, комбинирование по «И» и сброс (AC-39..AC-43), два empty-state (AC-23/E12,
 * AC-42), скелетоны загрузки и алерт ошибки с «Повторить» (DESIGN §4.2), удаление
 * через нативный диалог с оптимистичным применением (AC-21/22, E14).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { notesApi, tagsApi, type Note, type TagCount } from '../api/notes';
import { formatNotesCount } from '../lib/format';
import { noteTitle } from '../lib/note-text';
import { loadView, saveView, type ViewMode } from '../lib/view';
import { DeleteDialog } from '../components/DeleteDialog';
import { EmptyState } from '../components/EmptyState';
import { NoteItem } from '../components/NoteItem';
import { NoteListSkeleton } from '../components/Skeleton';
import { SearchBox } from '../components/SearchBox';
import { Segmented } from '../components/Segmented';
import { TagFilter } from '../components/TagFilter';
import { ErrorIcon, PlusIcon } from '../components/icons';

type LoadStatus = 'loading' | 'ready' | 'error';

export default function Notes() {
  const { logout } = useAuth();

  const [view, setView] = useState<ViewMode>(() => loadView());
  const [q, setQ] = useState('');
  const [tag, setTag] = useState<string | null>(null);

  const [notes, setNotes] = useState<Note[]>([]);
  const [tags, setTags] = useState<TagCount[]>([]);
  const [status, setStatus] = useState<LoadStatus>('loading');

  const [reloadKey, setReloadKey] = useState(0);
  const [tagsKey, setTagsKey] = useState(0);

  const [deleteTarget, setDeleteTarget] = useState<Note | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const searchRef = useRef<HTMLInputElement>(null);
  const loadedOnce = useRef(false);

  // Загрузка списка. При повторной загрузке (смена фильтра) скелетоны не
  // показываем — сохраняем предыдущий результат до прихода новых данных (§4.2.1).
  useEffect(() => {
    let active = true;
    if (!loadedOnce.current) setStatus('loading');
    notesApi
      .list({ q, tag })
      .then((response) => {
        if (!active) return;
        setNotes(response.items);
        loadedOnce.current = true;
        setStatus('ready');
      })
      .catch(() => {
        if (!active) return;
        setStatus('error');
      });
    return () => {
      active = false;
    };
  }, [q, tag, reloadKey]);

  // Теги для чипов-фильтров (перезапрашиваются после удаления — счётчики меняются).
  useEffect(() => {
    let active = true;
    tagsApi
      .list()
      .then((response) => {
        if (active) setTags(response.items);
      })
      .catch(() => {
        /* чипы не критичны для списка */
      });
    return () => {
      active = false;
    };
  }, [tagsKey]);

  const changeView = useCallback((next: ViewMode) => {
    setView(next);
    saveView(next);
  }, []);

  const resetFilters = useCallback(() => {
    setQ('');
    setTag(null);
    setDeleteError(null);
    searchRef.current?.focus();
  }, []);

  const toggleTag = useCallback((name: string) => {
    setTag((current) => (current === name ? null : name));
  }, []);

  const hasQuery = q.trim() !== '';
  const filtersActive = hasQuery || tag !== null;
  const isInitialLoading = status === 'loading' && !loadedOnce.current;

  const results = useMemo(() => {
    if (isInitialLoading) return <NoteListSkeleton />;

    if (status === 'error') {
      return (
        <div className="alert alert--error" role="alert">
          <span className="alert__icon">
            <ErrorIcon size={18} />
          </span>
          <div className="stack" style={{ gap: 'var(--sp-3)' }}>
            <div>
              <p className="alert__title">Не удалось загрузить заметки</p>
              <p className="small">
                Сервер не ответил. Данные на сервере не потеряны — просто повторите попытку.
              </p>
            </div>
            <div className="row">
              <button
                className="btn btn--sm btn--primary"
                type="button"
                onClick={() => setReloadKey((key) => key + 1)}
              >
                Повторить
              </button>
              <button className="btn btn--sm" type="button" onClick={() => void logout()}>
                Выйти и войти снова
              </button>
            </div>
          </div>
        </div>
      );
    }

    if (notes.length === 0) {
      return filtersActive ? (
        <EmptyState variant="no-results" onReset={resetFilters} />
      ) : (
        <EmptyState variant="no-notes" />
      );
    }

    return (
      <ul
        className={`results results--${view}`}
        data-notes-list
        data-view={view}
        aria-label="Список заметок"
      >
        {notes.map((note) => (
          <NoteItem key={note.id} note={note} onDelete={() => setDeleteTarget(note)} />
        ))}
      </ul>
    );
  }, [isInitialLoading, status, notes, view, filtersActive, resetFilters, logout]);

  async function confirmDelete() {
    const target = deleteTarget;
    if (!target) return;
    setDeleteError(null);
    setDeleteTarget(null);

    // Оптимистичное удаление без перезагрузки (AC-21).
    setNotes((prev) => prev.filter((note) => note.id !== target.id));
    try {
      await notesApi.remove(target.id);
      setTagsKey((key) => key + 1);
    } catch {
      setDeleteError('Не удалось удалить');
      setReloadKey((key) => key + 1); // откат: перечитываем актуальное состояние
    }
  }

  return (
    <section aria-labelledby="notes-title">
      <div className="page__head">
        <div className="stack" style={{ gap: 'var(--sp-1)' }}>
          <h1 id="notes-title">Мои заметки</h1>
          <p className="dim small">Сортировка: сначала обновлённые</p>
        </div>
        <Link className="btn btn--primary" to="/notes/new">
          <PlusIcon size={16} />
          Создать заметку
        </Link>
      </div>

      <section className="panel" aria-labelledby="search-h">
        <h2 className="sr-only" id="search-h">
          Поиск и фильтрация заметок
        </h2>
        <div className="panel__body stack">
          <div className="toolbar">
            <SearchBox ref={searchRef} value={q} onSearch={setQ} statusId="result-status" />
            <Segmented value={view} onChange={changeView} />
          </div>
          <TagFilter
            tags={tags}
            active={tag}
            onToggle={toggleTag}
            onReset={resetFilters}
            hasQuery={hasQuery}
          />
          {/* Живой регион результатов существует всегда: на него ссылается
              `aria-describedby` поля поиска (DESIGN §2.4/§2.6, NFR-16/20). */}
          <p
            className="small muted"
            id="result-status"
            role="status"
            aria-live="polite"
            data-result-status
          >
            {status === 'ready'
              ? `${formatNotesCount(notes.length)} — ${filtersActive ? 'по фильтру' : 'все заметки'}`
              : ''}
          </p>
        </div>
      </section>

      {deleteError ? (
        <div
          className="alert alert--error"
          role="alert"
          style={{ marginTop: 'var(--sp-4)' }}
        >
          <span className="alert__icon">
            <ErrorIcon size={18} />
          </span>
          <div>
            <p className="alert__title">{deleteError}</p>
            <p className="small">Заметка осталась на месте. Попробуйте ещё раз.</p>
          </div>
        </div>
      ) : null}

      <div data-results-wrap style={{ marginTop: 'var(--sp-5)' }}>
        {results}
      </div>

      <DeleteDialog
        open={deleteTarget !== null}
        noteTitle={deleteTarget ? noteTitle(deleteTarget) : ''}
        onConfirm={confirmDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </section>
  );
}
