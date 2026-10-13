/**
 * lib/markdown.ts — единый рендерер markdown → безопасный HTML (задача T-07).
 *
 * Конвейер: `markdown-it` (парсинг) → `DOMPurify` по allowlist (санитизация).
 * Один и тот же рендерер используется и в live-превью редактора (S4, T-09),
 * и в просмотре заметки (S5, T-10) — AC-31.
 *
 * Безопасность (DESIGN §8, PLAN §4.5, NFR-5):
 *  - `html: true` — markdown-it пропускает сырой HTML к санитайзеру, а DOMPurify
 *    по allowlist **вырезает** всё лишнее: `script`, `iframe`, `style` и их
 *    содержимое удаляются, `on*`-обработчики снимаются, `javascript:` в `href`
 *    блокируется; элемент вне allowlist разворачивается — его текст остаётся,
 *    но сам элемент не рендерится (`<b>текст</b>` → «текст», AC-46);
 *  - DOMPurify оставляет только allowlist тегов/атрибутов и безопасные схемы URI;
 *  - все ссылки получают `target="_blank"` + `rel="noopener noreferrer"`.
 */

import MarkdownIt from 'markdown-it';
import DOMPurify from 'dompurify';

/**
 * Разрешённые к выводу теги (DESIGN §8). Всё остальное не рендерится как элемент.
 * Заголовки начинаются с `h2`: `h1` в статье — это заголовок заметки (DESIGN §5.4),
 * уровень при этом нормализуется (минимальный заголовок заметки → `h2`).
 */
export const ALLOWED_TAGS: readonly string[] = [
  'strong',
  'em',
  'code',
  'pre',
  'ul',
  'ol',
  'li',
  'blockquote',
  'h2',
  'h3',
  'h4',
  'a',
  'hr',
  'table',
  'thead',
  'tbody',
  'tr',
  'th',
  'td',
  'p',
];

/** Разрешённые атрибуты. `target`/`rel` добавляются хук-обработчиком ссылок. */
const ALLOWED_ATTR: readonly string[] = ['href', 'title', 'target', 'rel'];

/** Наибольший уровень заголовка, допустимый в allowlist. */
const MAX_HEADING_LEVEL = 4;

const md = new MarkdownIt({
  html: true, // сырой HTML проходит через DOMPurify-allowlist (опасное вырезается)
  linkify: true, // «голые» URL становятся ссылками
  breaks: false,
  typographer: false,
});

/**
 * Нормализует уровни заголовков так, чтобы **минимальный** уровень в заметке
 * стал `h2`: `#` → `h2`, `##` → `h3`, а заметка без `#`, начинающаяся с `##`,
 * даёт `h2` (а не `h3`). Так внутри статьи не появляется второй `h1`, нет
 * пропуска уровней (`h1` страницы → `h2` статьи — без «дыры»), а уровни выше
 * `h4` прижимаются к `h4` (DESIGN §5.4, allowlist `h2–h4`).
 */
md.core.ruler.push('heading_normalize', (state) => {
  const opening = state.tokens.filter((token) => token.type === 'heading_open');
  if (opening.length === 0) return true;

  const levels = opening
    .map((token) => Number.parseInt(token.tag.slice(1), 10))
    .filter((level) => Number.isFinite(level));
  if (levels.length === 0) return true;

  const shift = 2 - Math.min(...levels);

  for (const token of state.tokens) {
    if (token.type !== 'heading_open' && token.type !== 'heading_close') continue;
    const level = Number.parseInt(token.tag.slice(1), 10);
    if (!Number.isFinite(level)) continue;
    token.tag = `h${Math.max(2, Math.min(level + shift, MAX_HEADING_LEVEL))}`;
  }
  return true;
});

// Ссылки открываются в новой вкладке, без доступа к opener (защита от reverse tabnabbing).
DOMPurify.addHook('afterSanitizeAttributes', (node: Element) => {
  if (node.tagName === 'A') {
    node.setAttribute('target', '_blank');
    node.setAttribute('rel', 'noopener noreferrer');
  }
});

/**
 * Рендерит markdown в безопасный HTML по allowlist.
 *
 * @param markdown исходный markdown заметки (хранится как raw-текст)
 * @returns санитизированный HTML-фрагмент; пустая строка для пустого/нестрокового ввода
 */
export function renderMarkdown(markdown: string): string {
  if (typeof markdown !== 'string' || markdown.length === 0) return '';

  const rawHtml = md.render(markdown);

  return DOMPurify.sanitize(rawHtml, {
    ALLOWED_TAGS: [...ALLOWED_TAGS],
    ALLOWED_ATTR: [...ALLOWED_ATTR],
    ALLOW_DATA_ATTR: false,
    ALLOW_ARIA_ATTR: false,
    KEEP_CONTENT: true,
  }) as string;
}
