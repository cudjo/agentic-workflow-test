/**
 * components/MdToolbar.tsx — toolbar форматирования markdown (DESIGN §2.7).
 *
 * `role="toolbar"` с группами `role="group"`, разделителями `role="separator"`;
 * у каждой кнопки `aria-label` + `title` + `aria-keyshortcuts`, глиф `aria-hidden`.
 * Вставка считается в `lib/editor.ts` (чистые функции) с учётом выделения textarea.
 * При клике мышью фокус возвращается в textarea, при активации с клавиатуры —
 * остаётся на кнопке (чтобы Tab продолжал обход toolbar).
 */
import { Fragment, useId, useRef, type CSSProperties, type ReactNode } from 'react';
import { applyToolbarOp, type EditResult, type ToolbarOp } from '../lib/editor';

interface ToolbarButton {
  key: string;
  label: string;
  glyph: ReactNode;
  op: ToolbarOp;
  shortcut?: string;
  data: Record<string, string>;
  glyphStyle?: CSSProperties;
}

interface ToolbarGroup {
  label: string;
  buttons: ToolbarButton[];
}

const GROUPS: ToolbarGroup[] = [
  {
    label: 'Заголовки',
    buttons: [
      {
        key: 'h1',
        label: 'Заголовок первого уровня',
        glyph: 'H1',
        op: { kind: 'prefix', prefix: '# ' },
        shortcut: 'Control+1',
        data: { 'data-md-prefix': '# ' },
      },
      {
        key: 'h2',
        label: 'Заголовок второго уровня',
        glyph: 'H2',
        op: { kind: 'prefix', prefix: '## ' },
        shortcut: 'Control+2',
        data: { 'data-md-prefix': '## ' },
      },
      {
        key: 'h3',
        label: 'Заголовок третьего уровня',
        glyph: 'H3',
        op: { kind: 'prefix', prefix: '### ' },
        shortcut: 'Control+3',
        data: { 'data-md-prefix': '### ' },
      },
    ],
  },
  {
    label: 'Начертание',
    buttons: [
      {
        key: 'bold',
        label: 'Жирный',
        glyph: 'B',
        glyphStyle: { fontWeight: 700 },
        op: { kind: 'wrap', before: '**', after: '**', placeholder: 'текст' },
        shortcut: 'Control+B',
        data: { 'data-md-insert': '**|**' },
      },
      {
        key: 'italic',
        label: 'Курсив',
        glyph: 'I',
        glyphStyle: { fontStyle: 'italic' },
        op: { kind: 'wrap', before: '*', after: '*', placeholder: 'текст' },
        shortcut: 'Control+I',
        data: { 'data-md-insert': '*|*' },
      },
    ],
  },
  {
    label: 'Списки',
    buttons: [
      {
        key: 'ul',
        label: 'Маркированный список',
        glyph: '•—',
        op: { kind: 'prefix', prefix: '- ' },
        data: { 'data-md-prefix': '- ' },
      },
      {
        key: 'ol',
        label: 'Нумерованный список',
        glyph: '1.—',
        op: { kind: 'prefix', prefix: '1. ' },
        data: { 'data-md-prefix': '1. ' },
      },
    ],
  },
  {
    label: 'Блоки и ссылки',
    buttons: [
      {
        key: 'code',
        label: 'Код в строке',
        glyph: '</>',
        glyphStyle: { fontFamily: 'var(--font-mono)' },
        op: { kind: 'wrap', before: '`', after: '`', placeholder: 'код' },
        data: { 'data-md-insert': '`|`' },
      },
      {
        key: 'codeblock',
        label: 'Блок кода',
        glyph: '[ ]',
        glyphStyle: { fontFamily: 'var(--font-mono)' },
        op: { kind: 'block', fence: '```', placeholder: 'код' },
        data: { 'data-md-block': '```' },
      },
      {
        key: 'quote',
        label: 'Цитата',
        glyph: '❝',
        op: { kind: 'prefix', prefix: '> ' },
        data: { 'data-md-prefix': '> ' },
      },
      {
        key: 'link',
        label: 'Ссылка',
        glyph: '🔗',
        op: { kind: 'link' },
        data: { 'data-md-link': '' },
      },
    ],
  },
];

export interface MdToolbarProps {
  value: string;
  textareaRef: React.RefObject<HTMLTextAreaElement>;
  onApply: (result: EditResult, focusTextarea: boolean) => void;
}

export function MdToolbar({ value, textareaRef, onApply }: MdToolbarProps) {
  const hintId = useId();
  const mouseSelection = useRef<{ start: number; end: number } | null>(null);

  function handleMouseDown(): void {
    const textarea = textareaRef.current;
    mouseSelection.current = textarea
      ? { start: textarea.selectionStart, end: textarea.selectionEnd }
      : null;
  }

  function handleClick(op: ToolbarOp): void {
    const textarea = textareaRef.current;
    const pending = mouseSelection.current;
    const start = pending?.start ?? textarea?.selectionStart ?? value.length;
    const end = pending?.end ?? textarea?.selectionEnd ?? value.length;
    onApply(applyToolbarOp(op, value, start, end), pending !== null);
    mouseSelection.current = null;
  }

  return (
    <>
      <div className="pane__toolbar">
        <div
          className="md-toolbar"
          role="toolbar"
          aria-label="Форматирование markdown"
          aria-describedby={hintId}
          data-md-toolbar
        >
          {GROUPS.map((group, index) => (
            <Fragment key={group.label}>
              {index > 0 ? (
                <span className="md-toolbar__sep" role="separator" aria-orientation="vertical" />
              ) : null}
              <div className="md-toolbar__group" role="group" aria-label={group.label}>
                {group.buttons.map((button) => (
                  <button
                    key={button.key}
                    className="md-toolbar__btn"
                    type="button"
                    aria-label={button.label}
                    title={button.label}
                    aria-keyshortcuts={button.shortcut}
                    onMouseDown={handleMouseDown}
                    onClick={() => handleClick(button.op)}
                    {...button.data}
                  >
                    <span className="md-toolbar__glyph" aria-hidden="true" style={button.glyphStyle}>
                      {button.glyph}
                    </span>
                  </button>
                ))}
              </div>
            </Fragment>
          ))}
        </div>
      </div>
      <p className="sr-only" id={hintId}>
        Кнопки применяются к выделенному тексту или вставляют заготовку в позицию курсора.
        Вставляемые фрагменты — обычный markdown-синтаксис.
      </p>
    </>
  );
}
