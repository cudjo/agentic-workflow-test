/**
 * pages/Editor.tsx — экран `S4` «Редактор заметки» (T-09).
 *
 * Создание (`/notes/new`) и редактирование (`/notes/:id/edit`):
 *   * заголовок (≤200, подсказка), теги (`TagInput`, лимиты 20/50),
 *     textarea markdown (≤100000, счётчик символов);
 *   * toolbar форматирования (DESIGN §2.7) с вставкой по выделению;
 *   * live-сплит превью (`renderMarkdown`, T-07); на узких — табы «Редактор/Просмотр»
 *     (переключение через `data-editor-mode`, CSS скрывает лишнюю панель);
 *   * явное сохранение POST/PATCH со статусом «Сохранено {время}» /
 *     «Есть несохранённые изменения», пустая заметка → запрет (AC-17/E1),
 *     ошибка сохранения → текст не теряется, статус не «сохранено» (E17);
 *   * диалог при уходе с несохранёнными правками (DESIGN §4.2.8) + `beforeunload`.
 */
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent as ReactMouseEvent,
} from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { notesApi, tagsApi } from '../api/notes';
import { Alert } from '../components/Alert';
import { MdToolbar } from '../components/MdToolbar';
import { TagInput } from '../components/TagInput';
import { UnsavedDialog } from '../components/UnsavedDialog';
import { EyeIcon, PencilIcon, SaveIcon } from '../components/icons';
import type { EditResult } from '../lib/editor';
import { formatNoteDate } from '../lib/format';
import { renderMarkdown } from '../lib/markdown';

const MAX_TITLE = 200;
const MAX_BODY = 100_000;

type LoadStatus = 'ready' | 'loading' | 'error';
type SaveStatus = 'idle' | 'saving' | 'error' | 'empty';
type EditorMode = 'editor' | 'preview';

interface Baseline {
  title: string;
  body: string;
  tags: string[];
}

/** Сравнение наборов тегов без учёта порядка и регистра (сервер сортирует). */
function sameTags(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const normalize = (list: string[]) => list.map((tag) => tag.toLowerCase()).sort();
  return normalize(a).join('\u0000') === normalize(b).join('\u0000');
}

export default function Editor() {
  const params = useParams();
  const navigate = useNavigate();

  const routeId = params.id && /^\d+$/.test(params.id) ? Number(params.id) : null;
  const isEdit = routeId !== null;

  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [tags, setTags] = useState<string[]>([]);
  const [suggestions, setSuggestions] = useState<string[]>([]);

  const [baseline, setBaseline] = useState<Baseline>({ title: '', body: '', tags: [] });
  const [savedAt, setSavedAt] = useState<string | null>(null);
  const [loadStatus, setLoadStatus] = useState<LoadStatus>(isEdit ? 'loading' : 'ready');
  const [saveStatus, setSaveStatus] = useState<SaveStatus>('idle');
  const [saving, setSaving] = useState(false);
  const [editorMode, setEditorMode] = useState<EditorMode>('editor');
  const [leaveOpen, setLeaveOpen] = useState(false);

  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const pendingSelection = useRef<{ start: number; end: number; focus: boolean } | null>(null);
  const loadedFor = useRef<number | null>(null);

  const tabEditorRef = useRef<HTMLButtonElement>(null);
  const tabPreviewRef = useRef<HTMLButtonElement>(null);
  const tabsMounted = useRef(false);

  // Применяем выделение после перерисовки (toolbar вернул фокус/выделение).
  useLayoutEffect(() => {
    const pending = pendingSelection.current;
    const textarea = textareaRef.current;
    if (pending && textarea) {
      if (pending.focus) textarea.focus();
      textarea.setSelectionRange(pending.start, pending.end);
      pendingSelection.current = null;
    }
  });

  // Подсказки тегов (datalist) — из уже использованных тегов пользователя.
  useEffect(() => {
    let active = true;
    tagsApi
      .list()
      .then((response) => {
        if (active) setSuggestions(response.items.map((tag) => tag.name));
      })
      .catch(() => {
        /* подсказки не критичны */
      });
    return () => {
      active = false;
    };
  }, []);

  // Загрузка заметки для редактирования.
  useEffect(() => {
    if (!isEdit || routeId === null) {
      setLoadStatus('ready');
      return;
    }
    if (loadedFor.current === routeId) {
      setLoadStatus('ready');
      return;
    }
    let active = true;
    setLoadStatus('loading');
    notesApi
      .get(routeId)
      .then((note) => {
        if (!active) return;
        loadedFor.current = routeId;
        const nextTitle = note.title ?? '';
        setTitle(nextTitle);
        setBody(note.bodyMarkdown);
        setTags(note.tags);
        setBaseline({ title: nextTitle, body: note.bodyMarkdown, tags: note.tags });
        setSavedAt(note.updatedAt);
        setLoadStatus('ready');
      })
      .catch(() => {
        if (active) setLoadStatus('error');
      });
    return () => {
      active = false;
    };
  }, [isEdit, routeId]);

  // Фокус на активном табе при переключении стрелками (roving tabindex).
  useEffect(() => {
    if (!tabsMounted.current) {
      tabsMounted.current = true;
      return;
    }
    (editorMode === 'editor' ? tabEditorRef : tabPreviewRef).current?.focus();
  }, [editorMode]);

  const dirty = useMemo(
    () => title !== baseline.title || body !== baseline.body || !sameTags(tags, baseline.tags),
    [title, body, tags, baseline],
  );

  // Предупреждение при закрытии вкладки/перезагрузке с несохранёнными правками.
  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = '';
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [dirty]);

  const markSaveIdle = useCallback(() => {
    setSaveStatus((prev) => (prev === 'error' || prev === 'empty' ? 'idle' : prev));
  }, []);

  const handleToolbarApply = useCallback((result: EditResult, focusTextarea: boolean) => {
    pendingSelection.current = {
      start: result.selectionStart,
      end: result.selectionEnd,
      focus: focusTextarea,
    };
    markSaveIdle();
    setBody(result.value);
  }, [markSaveIdle]);

  const save = useCallback(async (): Promise<boolean> => {
    if (!title.trim() && !body.trim()) {
      setSaveStatus('empty');
      return false;
    }
    const input = {
      title: title.trim() ? title : null,
      bodyMarkdown: body,
      tags,
    };
    setSaving(true);
    setSaveStatus('saving');
    try {
      const note =
        isEdit && routeId !== null
          ? await notesApi.update(routeId, input)
          : await notesApi.create(input);
      loadedFor.current = note.id;
      const nextTitle = note.title ?? '';
      setTitle(nextTitle);
      setBody(note.bodyMarkdown);
      setTags(note.tags);
      setBaseline({ title: nextTitle, body: note.bodyMarkdown, tags: note.tags });
      setSavedAt(note.updatedAt);
      setSaveStatus('idle');
      // После создания переходим на маршрут редактирования — следующие сохранения
      // будут PATCH (экран просмотра S5 появится в T-10).
      if (!isEdit) {
        navigate(`/notes/${note.id}/edit`, { replace: true });
      }
      return true;
    } catch {
      setSaveStatus('error');
      return false;
    } finally {
      setSaving(false);
    }
  }, [title, body, tags, isEdit, routeId, navigate]);

  const requestLeave = useCallback(() => {
    if (dirty) {
      setLeaveOpen(true);
      return;
    }
    navigate('/notes');
  }, [dirty, navigate]);

  function handleBackClick(event: ReactMouseEvent) {
    if (dirty) {
      event.preventDefault();
      setLeaveOpen(true);
    }
  }

  async function saveAndLeave() {
    const ok = await save();
    if (ok) {
      setLeaveOpen(false);
      navigate('/notes');
    }
    // При ошибке диалог остаётся открытым: пользователь видит алерт и может
    // повторить «Сохранить и выйти» или вернуться в редактор.
  }

  const loading = isEdit && loadStatus === 'loading';

  return (
    <section aria-labelledby="editor-title">
      <div className="page__head">
        <div className="stack" style={{ gap: 'var(--sp-2)' }}>
          <Link className="small" to="/notes" style={{ textDecoration: 'none' }} onClick={handleBackClick}>
            <span aria-hidden="true">←</span> Мои заметки
          </Link>
          <h1 id="editor-title">{isEdit ? 'Редактирование заметки' : 'Новая заметка'}</h1>
          {dirty ? (
            <p className="small dim" role="status" aria-live="polite" data-dirty-state>
              <span style={{ color: 'var(--c-warning)' }}>●</span> Есть несохранённые изменения
            </p>
          ) : savedAt ? (
            <p className="small dim" role="status" aria-live="polite" data-clean-state>
              Сохранено {formatNoteDate(savedAt)}
            </p>
          ) : null}
        </div>
        <div className="row wrap">
          <button className="btn" type="button" onClick={requestLeave}>
            Отмена
          </button>
          <button
            className="btn btn--primary"
            type="button"
            onClick={() => void save()}
            disabled={saving || loading}
            aria-busy={saving}
          >
            <SaveIcon size={16} />
            {saving ? 'Сохраняю…' : 'Сохранить'}
          </button>
        </div>
      </div>

      {saveStatus === 'empty' ? (
        <Alert
          variant="error"
          title="Заметка пустая"
          body="Нужен хотя бы заголовок или текст. Пустую заметку сохранить нельзя."
        />
      ) : null}
      {saveStatus === 'error' ? (
        <Alert
          variant="error"
          title="Не удалось сохранить"
          body="Сервер вернул ошибку. Текст остался в редакторе — попробуйте «Сохранить» ещё раз."
        />
      ) : null}

      {loading ? (
        <p className="small muted" role="status" aria-live="polite">
          Загрузка заметки…
        </p>
      ) : loadStatus === 'error' ? (
        <Alert
          variant="error"
          title="Не удалось загрузить заметку"
          body="Сервер не ответил или заметка удалена. Вернитесь к списку и попробуйте снова."
        />
      ) : (
        <div className="editor-shell" data-editor-mode={editorMode}>
          <div className="field">
            <label className="field__label" htmlFor="note-title">
              Заголовок <span className="dim">— необязательно</span>
            </label>
            <input
              className="input"
              id="note-title"
              name="title"
              type="text"
              maxLength={MAX_TITLE}
              placeholder="Например: План на неделю"
              value={title}
              aria-describedby="title-hint"
              onChange={(event) => {
                setTitle(event.target.value);
                markSaveIdle();
              }}
            />
            <span className="field__hint" id="title-hint">
              До 200 символов. Если пусто — заголовком станет первая строка текста (E3).
            </span>
          </div>

          <TagInput
            tags={tags}
            suggestions={suggestions}
            onChange={(next) => {
              setTags(next);
              markSaveIdle();
            }}
          />

          <div className="row between wrap" style={{ marginBottom: 'var(--sp-3)' }}>
            <div className="row-3 wrap">
              <h2 style={{ fontSize: 'var(--fs-18)' }}>Содержимое</h2>
              <div className="segmented editor-tabs" role="tablist" aria-label="Редактор или просмотр">
                <button
                  className="segmented__btn"
                  type="button"
                  role="tab"
                  id="tab-editor"
                  aria-controls="pane-editor"
                  aria-selected={editorMode === 'editor'}
                  tabIndex={editorMode === 'editor' ? 0 : -1}
                  ref={tabEditorRef}
                  onClick={() => setEditorMode('editor')}
                  onKeyDown={(event) => {
                    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
                      event.preventDefault();
                      setEditorMode((mode) => (mode === 'editor' ? 'preview' : 'editor'));
                    }
                  }}
                >
                  <PencilIcon size={16} />
                  Редактор
                </button>
                <button
                  className="segmented__btn"
                  type="button"
                  role="tab"
                  id="tab-preview"
                  aria-controls="pane-preview"
                  aria-selected={editorMode === 'preview'}
                  tabIndex={editorMode === 'preview' ? 0 : -1}
                  ref={tabPreviewRef}
                  onClick={() => setEditorMode('preview')}
                  onKeyDown={(event) => {
                    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') {
                      event.preventDefault();
                      setEditorMode((mode) => (mode === 'editor' ? 'preview' : 'editor'));
                    }
                  }}
                >
                  <EyeIcon size={16} />
                  Просмотр
                </button>
              </div>
            </div>
            <p className="tiny dim editor-split-note">
              Слева — markdown, справа — живое превью. На узких экранах они превращаются в
              переключатель.
            </p>
          </div>

          <div className="editor-grid">
            <section className="editor-pane" id="pane-editor" role="tabpanel" aria-labelledby="tab-editor">
              <div className="pane__header">
                <span className="pane__title">Markdown</span>
                <span className="tiny dim">Слева — исходник, справа — результат</span>
              </div>

              <MdToolbar value={body} textareaRef={textareaRef} onApply={handleToolbarApply} />

              <label className="sr-only" htmlFor="md-input">
                Текст заметки в markdown
              </label>
              <textarea
                className="md-input"
                id="md-input"
                name="body"
                spellCheck={false}
                data-md-input
                ref={textareaRef}
                value={body}
                maxLength={MAX_BODY}
                aria-describedby="md-hint"
                onChange={(event) => {
                  setBody(event.target.value);
                  markSaveIdle();
                }}
              />

              <div className="pane__foot">
                <span id="md-hint">
                  Текст сохраняется как raw markdown. Лимит — 100 000 символов.
                </span>
                <span className="mono" data-char-counter>
                  {body.length} / 100 000
                </span>
              </div>
            </section>

            <section className="preview-pane" id="pane-preview" role="tabpanel" aria-labelledby="tab-preview">
              <div className="pane__header">
                <span className="pane__title">Превью</span>
                <span className="tiny dim" aria-label="Рендер проходит через санитайзер">
                  🛡 через санитайзер
                </span>
              </div>
              <div className="md-preview">
                {body.trim() ? (
                  <article
                    className="md"
                    data-preview
                    dangerouslySetInnerHTML={{ __html: renderMarkdown(body) }}
                  />
                ) : (
                  <p className="dim small">Ничего не набрано</p>
                )}
              </div>
            </section>
          </div>
        </div>
      )}

      <UnsavedDialog
        open={leaveOpen}
        noteTitle={title.trim() || 'Новая заметка'}
        saving={saving}
        onStay={() => setLeaveOpen(false)}
        onDiscard={() => {
          setLeaveOpen(false);
          navigate('/notes');
        }}
        onSaveAndLeave={() => void saveAndLeave()}
      />
    </section>
  );
}
