/**
 * T-07 — тесты рендерера markdown (lib/markdown.ts).
 *
 * Покрывают приёмку:
 *  - AC-45/NFR-5: `<script>`/`on*`/`javascript:`/`iframe`/`style` не исполняются;
 *  - AC-46: `<b>текст</b>` как текст → детерминированный рендер по allowlist;
 *  - E8/E9: битый/незакрытый markdown не роняет рендер;
 *  - AC-31: один рендерер даёт идентичный HTML для превью и просмотра.
 */

import { describe, expect, it } from 'vitest';
import { ALLOWED_TAGS, renderMarkdown } from '../lib/markdown';

/** Разбирает HTML в отдельный элемент — приближает поведение браузера. */
function parse(html: string): HTMLDivElement {
  const div = document.createElement('div');
  div.innerHTML = html;
  return div;
}

describe('renderMarkdown — allowlist (AC-46)', () => {
  it('allowlist совпадает с DESIGN §8', () => {
    expect([...ALLOWED_TAGS].sort()).toEqual(
      [
        'a', 'blockquote', 'code', 'em', 'h2', 'h3', 'h4', 'hr', 'li', 'ol',
        'p', 'pre', 'strong', 'table', 'tbody', 'td', 'th', 'thead', 'tr', 'ul',
      ].sort(),
    );
  });

  it('рендерит разрешённые элементы markdown', () => {
    const html = renderMarkdown(
      '**жирный** и *курсив* и `код`\n\n> цитата\n\n- один\n- два\n\n1. первый\n\n---\n',
    );
    const div = parse(html);

    expect(div.querySelector('strong')).not.toBeNull();
    expect(div.querySelector('em')).not.toBeNull();
    expect(div.querySelector('code')).not.toBeNull();
    expect(div.querySelector('blockquote')).not.toBeNull();
    expect(div.querySelector('ul li')).not.toBeNull();
    expect(div.querySelector('ol li')).not.toBeNull();
    expect(div.querySelector('hr')).not.toBeNull();
  });

  it('заголовки начинаются с h2 и не выводят h1 (DESIGN §5.4)', () => {
    const html = renderMarkdown('# Первый\n\n## Второй\n\n### Третий\n\n#### Четвёртый\n');
    const div = parse(html);

    expect(div.querySelector('h1')).toBeNull();
    expect(div.querySelector('h2')?.textContent).toBe('Первый');
    expect(div.querySelector('h3')?.textContent).toBe('Второй');
    expect(div.querySelector('h4')?.textContent).toBe('Третий');
    // Уровни выше h4 прижимаются к h4.
    expect(div.querySelectorAll('h4').length).toBe(2);
    expect(html).not.toContain('<h1');
  });

  it('рендерит таблицу в пределах allowlist', () => {
    const html = renderMarkdown('| A | B |\n| - | - |\n| 1 | 2 |\n');
    const div = parse(html);
    expect(div.querySelector('table thead th')).not.toBeNull();
    expect(div.querySelectorAll('table tbody td').length).toBe(2);
  });

  it('<b>текст</b> показывается как текст, без <b>-элемента', () => {
    const html = renderMarkdown('<b>текст</b>');
    expect(html).not.toContain('<b>');
    expect(parse(html).querySelector('b')).toBeNull();
    // Элемент вне allowlist разворачивается: текст сохраняется, тег исчезает.
    expect(html).toContain('текст');
  });

  it('элемент вне allowlist (<div>) показывается как текст', () => {
    const html = renderMarkdown('<div class="x">внутри</div>');
    expect(html).not.toContain('<div');
    expect(parse(html).querySelector('div')).toBeNull();
    expect(html).toContain('внутри');
  });

  it('ссылки получают target=_blank и rel=noopener noreferrer', () => {
    const html = renderMarkdown('[пример](https://example.com)\n');
    const a = parse(html).querySelector('a');
    expect(a).not.toBeNull();
    expect(a?.getAttribute('href')).toBe('https://example.com');
    expect(a?.getAttribute('target')).toBe('_blank');
    expect(a?.getAttribute('rel')).toBe('noopener noreferrer');
  });

  it('пустой ввод → пустая строка', () => {
    expect(renderMarkdown('')).toBe('');
  });
});

describe('renderMarkdown — безопасность (AC-45 / NFR-5)', () => {
  it('<script> не исполняется и не попадает в DOM', () => {
    const html = renderMarkdown('<script>window.__xss = 1;</script>');
    expect(html).not.toContain('<script');
    const div = parse(html);
    expect(div.querySelector('script')).toBeNull();
    expect((window as unknown as { __xss?: number }).__xss).toBeUndefined();
  });

  it('markdown-ссылка с javascript: не создаёт опасный href', () => {
    const html = renderMarkdown('[клик](javascript:alert(1))');
    // markdown-it отклоняет опасную схему — ссылка не создаётся вовсе
    // (в выводе не остаётся ни одного <a> с исполняемым href).
    const anchors = parse(html).querySelectorAll('a');
    expect(anchors.length).toBe(0);
    anchors.forEach((a) => {
      expect(a.getAttribute('href') ?? '').not.toMatch(/^\s*javascript:/i);
    });
  });

  it('сырой <a href="javascript:…"> не получает исполняемый href', () => {
    const html = renderMarkdown('<a href="javascript:alert(1)">x</a>');
    const anchors = parse(html).querySelectorAll('a');
    anchors.forEach((a) => {
      expect(a.getAttribute('href') ?? '').not.toMatch(/javascript:/i);
    });
    // Ни у одной ссылки нет javascript:-адреса.
    expect(html).not.toMatch(/href="javascript:/i);
  });

  it('on*-обработчики вырезаются', () => {
    const html = renderMarkdown('<img src=x onerror="alert(1)"> <p onclick="alert(2)">y</p>');
    expect(html).not.toMatch(/onerror/i);
    expect(html).not.toMatch(/\son\w+=/i);
    expect(parse(html).querySelector('img')).toBeNull();
  });

  it('<iframe> вырезается', () => {
    const html = renderMarkdown('<iframe src="https://evil.example"></iframe>');
    expect(html).not.toContain('<iframe');
    expect(parse(html).querySelector('iframe')).toBeNull();
  });

  it('<style> и <svg onload> не проходят', () => {
    const html = renderMarkdown('<style>body{display:none}</style>\n\n<svg onload=alert(1)></svg>');
    expect(html).not.toContain('<style');
    expect(html).not.toContain('<svg');
    const div = parse(html);
    expect(div.querySelector('style')).toBeNull();
    expect(div.querySelector('svg')).toBeNull();
  });

  it('опасный ввод вместе с полезным: полезное рендерится, опасное — текстом', () => {
    const html = renderMarkdown('**важно**\n\n<script>alert(1)</script>');
    const div = parse(html);
    expect(div.querySelector('strong')?.textContent).toBe('важно');
    expect(div.querySelector('script')).toBeNull();
    expect(html).not.toContain('<script');
  });
});

describe('renderMarkdown — устойчивость (E8/E9)', () => {
  const broken = [
    '**незакрытый жирный',
    '[ссылка](незакрытая',
    '```\nнезакрытый код',
    '> цитата без конца',
    '# ',
    '***',
    '| a | b',
    '![изображение](broken',
    '<div',
    '`код',
  ];

  it.each(broken)('битый markdown не падает: %j', (input) => {
    expect(() => renderMarkdown(input)).not.toThrow();
    expect(typeof renderMarkdown(input)).toBe('string');
  });

  it('очень длинный и юникодный ввод не падает', () => {
    const long = `«Ёж» — тест\n\n${'а'.repeat(5000)}`;
    expect(() => renderMarkdown(long)).not.toThrow();
    expect(renderMarkdown(long)).toContain('Ёж');
  });
});

describe('renderMarkdown — единый рендерер (AC-31)', () => {
  const sample =
    '# Заголовок\n\nТекст **жирный**, *курсив*, [ссылка](https://example.com).\n\n' +
    '- список\n\n> цитата\n\n| A | B |\n| - | - |\n| 1 | 2 |\n';

  it('один и тот же ввод даёт идентичный HTML (превью === просмотр)', () => {
    // T-09 (превью) и T-10 (просмотр) вызывают одну функцию renderMarkdown —
    // при одинаковом входе результат обязан совпадать побайтово.
    expect(renderMarkdown(sample)).toBe(renderMarkdown(sample));
  });

  it('рендер детерминирован (идемпотентность при повторных вызовах)', () => {
    const first = renderMarkdown(sample);
    for (let i = 0; i < 5; i += 1) {
      expect(renderMarkdown(sample)).toBe(first);
    }
  });
});
