/**
 * lib/editor.ts — чистые операции toolbar форматирования markdown (DESIGN §2.7).
 *
 * Все функции не зависят от DOM: получают текущее значение textarea и позиции
 * выделения, возвращают новое значение и новое выделение. Это позволяет
 * покрыть поведение вставки unit-тестами, а компонент `MdToolbar` оставить
 * тонкой обёрткой над `applyToolbarOp`.
 *
 * Поведение (DESIGN §2.7):
 *   * префиксы — по строкам выделения (или строке с курсором), существующий
 *     маркер блока (`#…`, `- `, `* `, `+ `, `1. `, `> `) снимается, затем
 *     добавляется новый — повторный вызов **не дублирует** маркер;
 *   * обёртки (`**…**`, `*…*`, `` `…` ``) — вокруг выделения; повторный вызов
 *     снимает обёртку (toggle), маркеры не дублируются;
 *   * блок кода — ограждение из трёх обратных апострофов до и после;
 *   * ссылка — `[выделение](https://)`;
 *   * нет выделения — подставляется заготовка с плейсхолдером, он выделяется.
 */

export interface EditResult {
  value: string;
  selectionStart: number;
  selectionEnd: number;
}

export type ToolbarOp =
  | { kind: 'prefix'; prefix: string }
  | { kind: 'wrap'; before: string; after: string; placeholder: string }
  | { kind: 'block'; fence: string; placeholder: string }
  | { kind: 'link' };

/** Маркер блока в начале строки: заголовок / список / нумерация / цитата. */
const BLOCK_MARKER = /^([ \t]*)(?:#{1,6}[ \t]+|[-*+][ \t]+|\d+\.[ \t]+|>[ \t]*)/;

/** Границы строк, покрывающих выделение `[start, end)` (или строку курсора). */
function lineBounds(value: string, start: number, end: number): { from: number; to: number } {
  const from = value.lastIndexOf('\n', Math.max(0, start - 1)) + 1;
  const found = value.indexOf('\n', end);
  const to = found === -1 ? value.length : found;
  return { from, to };
}

/**
 * Префикс к каждой строке выделения (или строке курсора). Существующий
 * markdown-маркер блока снимается, поэтому повторное нажатие не дублирует `#`/`- `.
 * Для нумерованного списка (`1. `) строки нумеруются последовательно с 1.
 */
export function applyPrefix(
  value: string,
  start: number,
  end: number,
  prefix: string,
): EditResult {
  const { from, to } = lineBounds(value, start, end);
  const block = value.slice(from, to);
  const rawLines = block.split('\n');
  const hasContent = rawLines.some((line) => line.trim() !== '');
  const numbered = /^\d+\.\s*$/.test(prefix);

  let counter = 0;
  const lines = rawLines.map((line) => {
    // Пустые строки внутри многострочного выделения не размечаем.
    if (hasContent && line.trim() === '') return line;
    const stripped = line.replace(BLOCK_MARKER, '$1');
    if (numbered) {
      counter += 1;
      return `${counter}. ${stripped}`;
    }
    return `${prefix}${stripped}`;
  });

  const blockNew = lines.join('\n');
  const nextValue = value.slice(0, from) + blockNew + value.slice(to);
  return { value: nextValue, selectionStart: from, selectionEnd: from + blockNew.length };
}

/**
 * Обёртка выделения (`**…**`, `*…*`, `` `…` ``). Повторный вызов снимает обёртку
 * (toggle), поэтому маркеры не дублируются. Без выделения вставляется плейсхолдер
 * и выделяется целиком.
 */
export function applyWrap(
  value: string,
  start: number,
  end: number,
  before: string,
  after: string,
  placeholder: string,
): EditResult {
  const selected = value.slice(start, end);

  // Уже обёрнуто снаружи выделения → снять обёртку.
  const outerBefore = value.slice(Math.max(0, start - before.length), start);
  const outerAfter = value.slice(end, end + after.length);
  if (selected && outerBefore === before && outerAfter === after) {
    const inner = selected;
    const nextValue =
      value.slice(0, start - before.length) + inner + value.slice(end + after.length);
    return {
      value: nextValue,
      selectionStart: start - before.length,
      selectionEnd: start - before.length + inner.length,
    };
  }

  // Выделение само содержит маркеры → снять обёртку.
  if (
    selected.length >= before.length + after.length &&
    selected.startsWith(before) &&
    selected.endsWith(after)
  ) {
    const inner = selected.slice(before.length, selected.length - after.length);
    const nextValue = value.slice(0, start) + inner + value.slice(end);
    return { value: nextValue, selectionStart: start, selectionEnd: start + inner.length };
  }

  const content = selected || placeholder;
  const nextValue = value.slice(0, start) + before + content + after + value.slice(end);
  const innerStart = start + before.length;
  return {
    value: nextValue,
    selectionStart: innerStart,
    selectionEnd: innerStart + content.length,
  };
}

/** Блок кода: ограждающие строки из `fence` до и после содержимого. */
export function applyCodeBlock(
  value: string,
  start: number,
  end: number,
  fence: string,
  placeholder: string,
): EditResult {
  const selected = value.slice(start, end);
  const content = selected || placeholder;
  const lead = start > 0 && value[start - 1] !== '\n' ? '\n' : '';
  const trail = end < value.length && value[end] !== '\n' ? '\n' : '';
  const insert = `${lead}${fence}\n${content}\n${fence}${trail}`;
  const nextValue = value.slice(0, start) + insert + value.slice(end);
  const contentStart = start + lead.length + fence.length + 1;
  return {
    value: nextValue,
    selectionStart: contentStart,
    selectionEnd: contentStart + content.length,
  };
}

/** Ссылка: `[выделение](https://)`. Без выделения — `[текст](https://)`. */
export function applyLink(value: string, start: number, end: number): EditResult {
  const url = 'https://';
  const selected = value.slice(start, end);
  const text = selected || 'текст';
  const insert = `[${text}](${url})`;
  const nextValue = value.slice(0, start) + insert + value.slice(end);

  // При наличии выделения курсор встаёт на URL (его вводит пользователь);
  // без выделения — выделяется плейсхолдер-текст.
  if (selected) {
    const urlStart = start + 1 + selected.length + 2; // '[' + text + ']('
    return { value: nextValue, selectionStart: urlStart, selectionEnd: urlStart + url.length };
  }
  const textStart = start + 1;
  return {
    value: nextValue,
    selectionStart: textStart,
    selectionEnd: textStart + text.length,
  };
}

/** Применяет операцию toolbar к значению textarea и выделению. */
export function applyToolbarOp(
  op: ToolbarOp,
  value: string,
  start: number,
  end: number,
): EditResult {
  switch (op.kind) {
    case 'prefix':
      return applyPrefix(value, start, end, op.prefix);
    case 'wrap':
      return applyWrap(value, start, end, op.before, op.after, op.placeholder);
    case 'block':
      return applyCodeBlock(value, start, end, op.fence, op.placeholder);
    case 'link':
      return applyLink(value, start, end);
  }
}
