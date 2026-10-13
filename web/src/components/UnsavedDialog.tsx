/**
 * components/UnsavedDialog.tsx — диалог «Есть несохранённые изменения» (DESIGN §4.2.8).
 *
 * Нативный `<dialog>.showModal()` с тремя действиями:
 *   * «Остаться в редакторе» (`autofocus`) — отмена ухода;
 *   * «Выйти без сохранения» — уход с потерей правок;
 *   * «Сохранить и выйти» — сохранение, затем уход.
 * Esc/клик по backdrop = «остаться» (безопасное действие).
 */
import { useEffect, useId, useRef, type MouseEvent } from 'react';

export interface UnsavedDialogProps {
  open: boolean;
  /** Заголовок заметки для текста предупреждения. */
  noteTitle: string;
  onStay: () => void;
  onDiscard: () => void;
  onSaveAndLeave: () => void;
  saving?: boolean;
}

export function UnsavedDialog({
  open,
  noteTitle,
  onStay,
  onDiscard,
  onSaveAndLeave,
  saving = false,
}: UnsavedDialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const descId = useId();

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog || dialog.open) return;
    if (typeof dialog.showModal === 'function') {
      try {
        dialog.showModal();
        return;
      } catch {
        /* тестовое окружение без поддержки — открытый атрибут */
      }
    }
    dialog.setAttribute('open', '');
  }, [open]);

  if (!open) return null;

  function handleBackdropClick(event: MouseEvent<HTMLDialogElement>): void {
    if (event.target === event.currentTarget) onStay();
  }

  return (
    <dialog
      ref={ref}
      className="modal"
      aria-labelledby={titleId}
      aria-describedby={descId}
      onClose={onStay}
      onClick={handleBackdropClick}
    >
      <div className="modal__body">
        <h2 id={titleId} style={{ fontSize: 'var(--fs-18)' }}>
          Есть несохранённые изменения
        </h2>
        <p className="small muted" id={descId}>
          Если уйти сейчас, правки в «{noteTitle}» будут потеряны. Данные на сервере останутся прежними.
        </p>
      </div>
      <div className="modal__actions" style={{ flexWrap: 'wrap' }}>
        <button className="btn" type="button" onClick={onStay} autoFocus>
          Остаться в редакторе
        </button>
        <button className="btn btn--danger-quiet" type="button" onClick={onDiscard}>
          Выйти без сохранения
        </button>
        <button
          className="btn btn--primary"
          type="button"
          onClick={onSaveAndLeave}
          disabled={saving}
          aria-busy={saving}
        >
          Сохранить и выйти
        </button>
      </div>
    </dialog>
  );
}
