/**
 * a11y-css.test.ts — статический контракт CSS для доступности и адаптива (T-11).
 *
 * jsdom не считает раскладку, поэтому проверки брейкпоинтов и пользовательских
 * предпочтений идут по исходным стилям (импорт `?raw`), а фактический рендер
 * на ширинах 1280/1024/860/640 проверяется браузером (см. PROGRESS T-11).
 *
 * Покрывается: DESIGN §3.10 (брейкпоинты), §5.5 (reduced-motion, contrast,
 * fallback без backdrop-filter), §5.6 (16px у инпутов, зоны нажатия),
 * §4.2.10 (видимый фокус), §6.2/§6.3 (плотность стекла, blur только на контейнере).
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

// Исходные стили читаем с диска: vitest не обрабатывает CSS (`test.css: false`),
// поэтому импорт `?raw` вернул бы пустую строку. Путь — от файла теста
// (`import.meta.url`), относительная резолюция URL в jsdom не используется.
const STYLES_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'styles');
const read = (name: string): string => readFileSync(join(STYLES_DIR, name), 'utf8');

const GLASS = read('glass.css');
const BASE = read('base.css');
const TOKENS = read('tokens.css');

/** Вырезает тело media-блока по точному условию (с учётом вложенности). */
function mediaBlock(css: string, condition: string): string {
  const start = css.indexOf(`@media (${condition})`);
  expect(start, `нет @media (${condition})`).toBeGreaterThan(-1);
  const open = css.indexOf('{', start);
  let depth = 0;
  for (let i = open; i < css.length; i += 1) {
    if (css[i] === '{') depth += 1;
    else if (css[i] === '}') {
      depth -= 1;
      if (depth === 0) return css.slice(open + 1, i);
    }
  }
  throw new Error(`не найден конец @media (${condition})`);
}

const noSpace = (css: string): string => css.replace(/\s+/g, ' ');
/** Убирает комментарии — иначе упоминание правил в пояснениях ломает проверки. */
const noComments = (css: string): string => css.replace(/\/\*[\s\S]*?\*\//g, '');

describe('CSS: брейкпоинты 1280/1024/860/640 (DESIGN §3.10)', () => {
  it('инпуты всегда 16px (антизум iOS), поле markdown — 16px на мобильном (§2.12/§5.6)', () => {
    expect(noSpace(GLASS)).toMatch(/\.input, \.textarea, \.select \{[^}]*font-size: var\(--fs-16\)/);
    const mobile = noSpace(mediaBlock(GLASS, 'max-width: 640px'));
    expect(mobile).toMatch(/\.md-input \{ font-size: var\(--fs-16\)/);
  });

  it('≤1024px: сплит редактора превращается в табы Редактор/Просмотр (NFR-23)', () => {
    expect(noSpace(GLASS)).toMatch(/\.editor-tabs \{ display: none/);
    const block = noSpace(mediaBlock(GLASS, 'max-width: 1024px'));
    expect(block).toMatch(/\.editor-tabs \{ display: inline-flex/);
    expect(block).toMatch(/\.editor-shell\[data-editor-mode="editor"\] \.preview-pane \{ display: none/);
    expect(block).toMatch(/\.editor-shell\[data-editor-mode="preview"\] \.editor-pane \{ display: none/);
    expect(block).toMatch(/\.editor-grid \{ grid-template-columns: 1fr/);
    expect(block).toMatch(/\.auth__aside \{ display: none/);
    expect(block).toMatch(/--container: 100%/);
  });

  it('≥1025px: сплит 50/50 и брендовая панель форм (DESIGN §3.10)', () => {
    const base = noSpace(GLASS);
    expect(base).toMatch(/\.editor-grid \{ display: grid; grid-template-columns: 1fr 1fr/);
    expect(base).toMatch(/\.auth \{ min-height: 100vh; display: grid; grid-template-columns: 1fr 1fr/);
  });

  it('≤860px: фрагмент текста в списке скрыт, теги уже', () => {
    const block = noSpace(mediaBlock(GLASS, 'max-width: 860px'));
    expect(block).toMatch(/\.results--list \.note-item__snippet \{ display: none/);
    expect(block).toMatch(/\.results--list \.note-item__tags \{ max-width: 140px/);
    // Каскад: правило ≤860px должно идти после ≤1024px (иначе max-width:180px
    // из блока ≤1024px перебивало бы 140px — правило оказалось бы мёртвым).
    expect(GLASS.indexOf('@media (max-width: 860px)')).toBeGreaterThan(
      GLASS.indexOf('@media (max-width: 1024px)'),
    );
  });

  it('641–900px: ровно 2 колонки плиток', () => {
    const block = noSpace(mediaBlock(GLASS, 'max-width: 900px) and (min-width: 641px'));
    expect(block).toMatch(/\.results--grid \{ grid-template-columns: repeat\(2, minmax\(0, 1fr\)\)/);
  });

  it('≤640px: одна плитка в колонку, список в две строки, тулбары/фильтры в столбик, кнопки диалога на всю ширину', () => {
    const block = noSpace(mediaBlock(GLASS, 'max-width: 640px'));
    expect(block).toMatch(/\.results--grid \{ grid-template-columns: 1fr/);
    expect(block).toMatch(/\.results--grid \.note-item \{ min-height: 0/);
    expect(block).toMatch(/\.results--list \.note-item__main \{ flex-basis: 100%/);
    expect(block).toMatch(/\.toolbar \{ flex-direction: column/);
    // Поиск в колоночном toolbar не должен растягиваться по высоте (flex-basis по вертикали).
    expect(block).toMatch(/\.toolbar \.search \{ flex: 0 0 auto/);
    expect(block).toMatch(/\.filterbar \{ flex-direction: column/);
    expect(block).toMatch(/\.modal__actions \{ flex-direction: column-reverse/);
    expect(block).toMatch(/\.modal__actions \.btn \{ width: 100%/);
    expect(block).toMatch(/\.userchip__name \{ display: none/);
    expect(block).toMatch(/--topbar-h: 58px; --glass-blur: 14px/);
  });
});

describe('CSS: предпочтения пользователя (DESIGN §5.5)', () => {
  it('prefers-reduced-motion гасит mesh-дрейф, shimmer и hover-подъёмы', () => {
    const block = noSpace(mediaBlock(GLASS, 'prefers-reduced-motion: reduce'));
    expect(block).toMatch(/body::before \{ animation: none/);
    expect(block).toMatch(/animation-duration: \.01ms !important/);
    expect(block).toMatch(/animation-iteration-count: 1 !important/);
    expect(block).toMatch(/transition-duration: \.01ms !important/);
    expect(block).toMatch(/\.results--grid \.note-item:hover, \.screen-card:hover \{ transform: none/);
  });

  it('prefers-contrast: more уплотняет стекло и затемняет границы/текст', () => {
    const block = noSpace(mediaBlock(TOKENS, 'prefers-contrast: more'));
    expect(block).toMatch(/--glass-bg-hi: rgb\(255 255 255 \/ \.98\)/);
    expect(block).toMatch(/--glass-bg: rgb\(255 255 255 \/ \.95\)/);
    expect(block).toMatch(/--glass-bg-lo: rgb\(255 255 255 \/ \.92\)/);
    expect(block).toMatch(/--c-border: rgb\(15 23 42 \/ \.3\)/);
    expect(block).toMatch(/--c-text-2: #2b3648/);
    expect(block).toMatch(/--c-text-3: #39465a/);
  });

  it('fallback без backdrop-filter делает стекло почти непрозрачным, вёрстка не меняется', () => {
    const support = '@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px)))';
    expect(GLASS).toContain(support);
    const fallback = noSpace(GLASS.slice(GLASS.indexOf(support)));
    expect(fallback).toMatch(/\.input, \.textarea, \.select \{ background-color: rgb\(255 255 255 \/ \.96\)/);
    expect(fallback).toMatch(/\.md-input \{ background-color: rgb\(255 255 255 \/ \.95\)/);
    expect(fallback).toMatch(/\.segmented__btn\[aria-pressed="true"\][^{]*\{ background-color: #fff/);
    expect(fallback).toMatch(/body::before \{ filter: blur\(46px\) saturate\(105%\); opacity: \.9/);

    const tokens = noSpace(TOKENS.slice(TOKENS.indexOf(support)));
    expect(tokens).toMatch(/--glass-bg-hi: rgb\(255 255 255 \/ \.96\)/);
    expect(tokens).toMatch(/--glass-bg: rgb\(255 255 255 \/ \.94\)/);
    expect(tokens).toMatch(/--glass-bg-chrome: rgb\(255 255 255 \/ \.95\)/);
    expect(tokens).toMatch(/--glass-bg-lo: rgb\(255 255 255 \/ \.9\)/);
  });
});

describe('CSS: фокус, контраст и стекло (DESIGN §4.2.10, §5.1, §6.3)', () => {
  it('видимое кольцо фокуса с белым «поясом» на стекле', () => {
    const focus = noSpace(BASE.slice(BASE.indexOf(':focus-visible')));
    expect(focus).toMatch(/outline: 3px solid var\(--c-focus\)/);
    expect(focus).toMatch(/outline-offset: 2px/);
    expect(focus).toMatch(/box-shadow: 0 0 0 6px rgb\(255 255 255 \/ \.55\)/);
    // Поле markdown — кольцо внутрь панели, иначе обрезается.
    expect(noSpace(GLASS)).toMatch(/\.md-input \{[^}]*outline-offset: -4px/);
    expect(noSpace(BASE)).toMatch(/\.skip-link:focus \{ top: /);
    expect(noSpace(BASE)).toMatch(/\.sr-only \{ position: absolute; width: 1px; height: 1px/);
  });

  it('стили не применяют contain: paint (обрезало бы кольца фокуса)', () => {
    expect(noComments(GLASS)).not.toMatch(/contain:\s*paint/);
    expect(noComments(BASE)).not.toMatch(/contain:\s*paint/);
  });

  it('blur в режиме списка — только на контейнере, строки прозрачные (§6.3, NFR-1)', () => {
    const listItem = noSpace(GLASS).match(/\.results--list \.note-item \{[^}]*\}/)?.[0] ?? '';
    expect(listItem).toContain('backdrop-filter: none');
    expect(listItem).toContain('background-color: transparent');
    const container = noSpace(GLASS).match(/\.results--list \{[^}]*\}/)?.[0] ?? '';
    expect(container).toContain('backdrop-filter: blur(var(--glass-blur))');
  });

  it('плотность стекла по уровням: формы/диалоги .84, панели .68, хром .58, лёгкий .42 (§6.2)', () => {
    const tokens = noSpace(TOKENS);
    expect(tokens).toMatch(/--glass-bg-hi: rgb\(255 255 255 \/ \.84\)/);
    expect(tokens).toMatch(/--glass-bg: rgb\(255 255 255 \/ \.68\)/);
    expect(tokens).toMatch(/--glass-bg-chrome: rgb\(255 255 255 \/ \.58\)/);
    expect(tokens).toMatch(/--glass-bg-lo: rgb\(255 255 255 \/ \.42\)/);
  });
});
