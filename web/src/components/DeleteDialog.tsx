/**
 * components/DeleteDialog.tsx — подтверждение удаления (DESIGN §2.8/§4.2.9).
 *
 * Нативный `<dialog>.showModal()`: `aria-labelledby` → заголовок, `aria-describedby`
 * → текст, фокус на безопасном «Отмена»; Esc (и клик по backdrop) = отмена,
 * фокус возвращается на инициатора (см. `useModalDialog`, NFR-15/§5.3).
 * Подтверждение не удаляет здесь — вызывает `onConfirm` (страница делает
 * оптимистичное удаление), при ошибке алерт показывает страница (E17).
 */
import { useId, useRef, type MouseEvent } from 'react';
import { TrashIcon } from './icons';
import { useModalDialog } from './useModalDialog';

interface DeleteDialogProps {
  open: boolean;
  noteTitle: string;
  onConfirm: () => void;
  onCancel: () => void;
  pending?: boolean;
}

export function DeleteDialog({
  open,
  noteTitle,
  onConfirm,
  onCancel,
  pending = false,
}: DeleteDialogProps) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const descId = useId();

  useModalDialog(open, ref, onCancel);

  if (!open) return null;

  function handleBackdropClick(event: MouseEvent<HTMLDialogElement>) {
    if (event.target === event.currentTarget) onCancel();
  }

  return (
    <dialog
      ref={ref}
      className="modal"
      aria-labelledby={titleId}
      aria-describedby={descId}
      onClose={onCancel}
      onClick={handleBackdropClick}
    >
      <div className="modal__body">
        <div className="row-3">
          <span
            className="empty__art"
            aria-hidden="true"
            style={{ width: 44, height: 44, background: 'var(--c-danger-soft)', color: 'var(--c-danger)' }}
          >
            <TrashIcon size={22} />
          </span>
          <div className="stack" style={{ gap: 2 }}>
            <h2 id={titleId} style={{ fontSize: 'var(--fs-18)' }}>
              Удалить заметку?
            </h2>
            <p className="small dim">Это действие нельзя отменить</p>
          </div>
        </div>
        <p className="small muted" id={descId}>
          Заметка «{noteTitle}» будет удалена навсегда. Корзины нет — восстановить не получится.
        </p>
      </div>
      <div className="modal__actions">
        <button className="btn" type="button" onClick={onCancel} autoFocus>
          Отмена
        </button>
        <button className="btn btn--danger" type="button" onClick={onConfirm} disabled={pending}>
          Удалить заметку
        </button>
      </div>
    </dialog>
  );
}
