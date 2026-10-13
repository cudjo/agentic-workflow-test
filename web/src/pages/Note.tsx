/**
 * pages/Note.tsx — экран `S5` «Просмотр заметки» (T-10, `/notes/:id`).
 *
 *   * загрузка заметки (`GET /api/notes/:id`) со **скелетоном статьи** (§4.2.1);
 *   * чужой/несуществующий id → состояние «Заметка не найдена» (404, без
 *     раскрытия существования — AC-11/Q-A7); прочие ошибки — алерт с «Повторить»;
 *   * рендер markdown тем же `renderMarkdown` (T-07), что и превью редактора —
 *     `article.md` (AC-31), аккуратные мета и действия;
 *   * **один `h1`** на страницу — заголовок заметки (`noteTitle`, для заметки без
 *     заголовка — первая строка текста); markdown-заголовки начинаются с `h2`
 *     (рендерер сдвигает `#` → `h2`, DESIGN §5.4);
 *   * мета: даты «8 окт 2026, 20:15», размер и теги — **обычным текстом**
 *     (не `innerHTML`, AC-47/NFR-14);
 *   * действия «Редактировать» (`/notes/:id/edit`) и «Удалить» (переиспользует
 *     `DeleteDialog`, после подтверждения — возврат к списку `/notes`, E13),
 *     ссылка «← Мои заметки».
 */
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ApiError } from '../api/client';
import { notesApi, type Note as NoteModel } from '../api/notes';
import { Alert } from '../components/Alert';
import { DeleteDialog } from '../components/DeleteDialog';
import { NoteArticleSkeleton } from '../components/Skeleton';
import { ClockIcon, ErrorIcon, PencilIcon, TrashIcon } from '../components/icons';
import { formatCharsCount, formatNoteDateFull, formatNoteDateOnly } from '../lib/format';
import { renderMarkdown } from '../lib/markdown';
import { noteTitle } from '../lib/note-text';

type LoadStatus = 'loading' | 'ready' | 'notfound' | 'error';

export default function Note() {
  const params = useParams();
  const navigate = useNavigate();
  const routeId = params.id && /^\d+$/.test(params.id) ? Number(params.id) : null;

  const [note, setNote] = useState<NoteModel | null>(null);
  const [status, setStatus] = useState<LoadStatus>('loading');
  const [reloadKey, setReloadKey] = useState(0);

  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const deleteButtonRef = useRef<HTMLButtonElement>(null);

  // Загрузка заметки. Чужой и несуществующий id неразличимы: сервер отдаёт 404.
  useEffect(() => {
    if (routeId === null) {
      setNote(null);
      setStatus('notfound');
      return;
    }
    let active = true;
    setStatus('loading');
    setNote(null);
    notesApi
      .get(routeId)
      .then((loaded) => {
        if (!active) return;
        setNote(loaded);
        setStatus('ready');
      })
      .catch((error: unknown) => {
        if (!active) return;
        setStatus(error instanceof ApiError && error.status === 404 ? 'notfound' : 'error');
      });
    return () => {
      active = false;
    };
  }, [routeId, reloadKey]);

  const confirmDelete = useCallback(async () => {
    if (!note) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await notesApi.remove(note.id);
      setDeleteOpen(false);
      // Удаление открытой заметки → возврат к списку (E13).
      navigate('/notes');
    } catch {
      setDeleting(false);
      setDeleteOpen(false);
      setDeleteError('Не удалось удалить');
      // Фокус возвращается на инициатора действия (§4.2.3).
      deleteButtonRef.current?.focus();
    }
  }, [note, navigate]);

  /* --------------------------- не найдена / ошибка --------------------------- */

  if (status === 'loading') {
    return <NoteArticleSkeleton />;
  }

  if (status === 'notfound') {
    return (
      <div className="empty" data-note-notfound>
        <div className="empty__art" aria-hidden="true">
          <ErrorIcon size={30} />
        </div>
        <h1 className="empty__title">Заметка не найдена</h1>
        <p className="empty__text">
          Возможно, она удалена или ссылка неверна. Чужая заметка выглядит так же, как несуществующая —
          мы не подтверждаем её существование.
        </p>
        <Link className="btn btn--primary" to="/notes">
          К моим заметкам
        </Link>
      </div>
    );
  }

  if (status === 'error' || !note) {
    return (
      <div className="stack" style={{ gap: 'var(--sp-4)' }}>
        <Link className="small" to="/notes" style={{ textDecoration: 'none' }}>
          <span aria-hidden="true">←</span> Мои заметки
        </Link>
        <h1>Не удалось загрузить заметку</h1>
        <Alert
          variant="error"
          title="Сервер не ответил"
          body="Данные на сервере не потеряны — просто повторите попытку."
        />
        <div className="row">
          <button
            className="btn btn--primary btn--sm"
            type="button"
            onClick={() => setReloadKey((key) => key + 1)}
          >
            Повторить
          </button>
          <Link className="btn btn--sm" to="/notes">
            К моим заметкам
          </Link>
        </div>
      </div>
    );
  }

  /* --------------------------------- заметка --------------------------------- */

  const title = noteTitle(note);
  const html = renderMarkdown(note.bodyMarkdown);

  return (
    <>
      <section aria-labelledby="note-title">
        <Link className="small" to="/notes" style={{ textDecoration: 'none' }}>
          <span aria-hidden="true">←</span> Мои заметки
        </Link>

        <div className="page__head" style={{ marginTop: 'var(--sp-3)' }}>
          <div className="stack" style={{ gap: 'var(--sp-3)' }}>
            <h1 id="note-title">{title}</h1>
            <div className="row-3 wrap small dim">
              <span className="row">
                <ClockIcon size={14} />
                <span>
                  Обновлена{' '}
                  <time dateTime={note.updatedAt}>{formatNoteDateFull(note.updatedAt)}</time>
                </span>
              </span>
              <span className="meta-dot" aria-hidden="true">
                ·
              </span>
              <span>
                Создана <time dateTime={note.createdAt}>{formatNoteDateOnly(note.createdAt)}</time>
              </span>
              <span className="meta-dot" aria-hidden="true">
                ·
              </span>
              <span>{formatCharsCount(note.bodyMarkdown.length)}</span>
            </div>
            {/* Теги — статичный текст (NFR-14), но с именем группы, чтобы
                скринридер объявлял их вместе с заметкой. */}
            <div className="row wrap" role="group" aria-label="Теги заметки">
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
          </div>

          <div className="row wrap">
            <Link className="btn btn--primary" to={`/notes/${note.id}/edit`}>
              <PencilIcon size={16} />
              Редактировать
            </Link>
            <button
              className="btn btn--danger-quiet"
              type="button"
              ref={deleteButtonRef}
              onClick={() => {
                setDeleteError(null);
                setDeleteOpen(true);
              }}
            >
              <TrashIcon size={16} />
              Удалить
            </button>
          </div>
        </div>

        {deleteError ? (
          <div style={{ marginTop: 'var(--sp-4)' }}>
            <Alert
              variant="error"
              title={deleteError}
              body="Заметка осталась на месте. Попробуйте ещё раз."
            />
          </div>
        ) : null}

        {/* Отрендеренный markdown: тот же `renderMarkdown`, что и в превью S4 (AC-31). */}
        <article className="md article-body" dangerouslySetInnerHTML={{ __html: html }} />
      </section>

      <DeleteDialog
        open={deleteOpen}
        noteTitle={title}
        pending={deleting}
        onConfirm={confirmDelete}
        onCancel={() => setDeleteOpen(false)}
      />
    </>
  );
}
