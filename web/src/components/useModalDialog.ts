/**
 * components/useModalDialog.ts — общая механика нативного модального диалога
 * (DESIGN §5.3, NFR-15).
 *
 *   * открытие через `<dialog>.showModal()` (fallback — атрибут `open`, если
 *     окружение не поддерживает модальный режим);
 *   * при открытии фокус гарантированно внутри диалога — на «безопасном»
 *     действии (`autofocus`, иначе первая доступная кнопка). Так он не остаётся
 *     «за» модальным окном ни в браузере, ни в тестовом окружении;
 *   * `Escape` — единообразно выполняет безопасное действие (в браузере это
 *     нативное закрытие диалога, в jsdom такого поведения нет);
 *   * при закрытии диалог закрывается через `close()` и **фокус возвращается
 *     инициатору** — кнопке или ссылке, открывшей диалог (§5.3).
 */
import { useEffect, useRef, type RefObject } from 'react';

const FOCUSABLE = 'button:not([disabled]), a[href], input:not([disabled]), select, textarea';

export function useModalDialog(
  open: boolean,
  ref: RefObject<HTMLDialogElement | null>,
  onEscape: () => void,
): void {
  const restoreRef = useRef<HTMLElement | null>(null);

  // Инициатора запоминаем до commit: `autoFocus` внутри диалога применяется уже
  // после отрисовки, поэтому `document.activeElement` в эффекте указывал бы на
  // кнопку самого диалога, а не на элемент, который его открыл. Сбрасываем
  // значение в cleanup эффекта (не в рендере) — иначе к моменту возврата фокуса
  // рендер с `open === false` уже обнулил бы ссылку.
  if (open && restoreRef.current === null) {
    restoreRef.current =
      typeof document === 'undefined' ? null : (document.activeElement as HTMLElement | null);
  }

  // Показ нативного диалога + возврат фокуса инициатору при закрытии.
  useEffect(() => {
    if (!open) return undefined;
    const dialog = ref.current;
    if (!dialog) return undefined;

    if (!dialog.open) {
      if (typeof dialog.showModal === 'function') {
        try {
          dialog.showModal();
        } catch {
          dialog.setAttribute('open', '');
        }
      } else {
        dialog.setAttribute('open', '');
      }
    }

    if (!dialog.contains(document.activeElement)) {
      const target = dialog.querySelector<HTMLElement>(`[autofocus], ${FOCUSABLE}`);
      if (target && typeof target.focus === 'function') {
        target.focus();
      } else {
        if (!dialog.hasAttribute('tabindex')) dialog.setAttribute('tabindex', '-1');
        dialog.focus();
      }
    }

    return () => {
      if (dialog.open && typeof dialog.close === 'function') {
        try {
          dialog.close();
        } catch {
          /* диалог уже вне документа — закрывать нечего */
        }
      }
      const restore = restoreRef.current;
      restoreRef.current = null;
      if (
        restore &&
        restore !== document.body &&
        document.contains(restore) &&
        typeof restore.focus === 'function'
      ) {
        restore.focus();
      }
    };
  }, [open, ref]);

  // Esc = безопасное действие (в браузере нативное закрытие, в jsdom — нет).
  useEffect(() => {
    if (!open) return undefined;
    const dialog = ref.current;
    if (!dialog) return undefined;

    const handleKeyDown = (event: KeyboardEvent): void => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      onEscape();
    };

    dialog.addEventListener('keydown', handleKeyDown);
    return () => dialog.removeEventListener('keydown', handleKeyDown);
  }, [open, onEscape, ref]);
}
