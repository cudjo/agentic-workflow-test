/**
 * editor-lib.test.ts — unit-тесты чистой логики toolbar (DESIGN §2.7).
 *
 * Проверяем операции вставки по выделению: префиксы (без дублирования маркеров),
 * обёртки (toggle), блок кода, ссылка; позиции выделения после операции.
 */
import { describe, expect, it } from 'vitest';
import {
  applyCodeBlock,
  applyLink,
  applyPrefix,
  applyToolbarOp,
  applyWrap,
} from '../lib/editor';

describe('префиксы', () => {
  it('на пустой строке вставляет маркер заголовка', () => {
    expect(applyPrefix('', 0, 0, '# ')).toEqual({ value: '# ', selectionStart: 0, selectionEnd: 2 });
  });

  it('повторное применение не дублирует маркер (# не удваивается)', () => {
    const once = applyPrefix('Заголовок', 0, 9, '# ');
    expect(once.value).toBe('# Заголовок');
    const twice = applyPrefix(once.value, once.selectionStart, once.selectionEnd, '# ');
    expect(twice.value).toBe('# Заголовок');
  });

  it('снимает прежний маркер блока перед установкой нового', () => {
    // Список → заголовок: маркер `- ` снимается, `# ` добавляется.
    expect(applyPrefix('- пункт', 2, 2, '# ').value).toBe('# пункт');
    // Цитата → маркированный список.
    expect(applyPrefix('> текст', 2, 2, '- ').value).toBe('- текст');
  });

  it('применяется построчно к выделенному блоку', () => {
    const result = applyPrefix('a\nb', 0, 3, '- ');
    expect(result.value).toBe('- a\n- b');
    expect(result.selectionStart).toBe(0);
    expect(result.selectionEnd).toBe(result.value.length);
  });

  it('нумерованный список нумерует строки с 1', () => {
    expect(applyPrefix('a\nb', 0, 3, '1. ').value).toBe('1. a\n2. b');
  });

  it('не размечает пустые строки внутри многострочного выделения', () => {
    expect(applyPrefix('a\n\nb', 0, 4, '> ').value).toBe('> a\n\n> b');
  });
});

describe('обёртки (начертание/инлайн-код)', () => {
  it('оборачивает выделение', () => {
    expect(applyWrap('мир', 0, 3, '**', '**', 'текст')).toEqual({
      value: '**мир**',
      selectionStart: 2,
      selectionEnd: 5,
    });
  });

  it('без выделения вставляет и выделяет плейсхолдер', () => {
    expect(applyWrap('', 0, 0, '**', '**', 'текст')).toEqual({
      value: '**текст**',
      selectionStart: 2,
      selectionEnd: 7,
    });
  });

  it('повторное применение снимает обёртку (toggle, без дубликатов)', () => {
    const result = applyWrap('**мир**', 2, 5, '**', '**', 'текст');
    expect(result.value).toBe('мир');
    expect(result.selectionStart).toBe(0);
    expect(result.selectionEnd).toBe(3);
  });

  it('снимает обёртку, если выделение захватывает маркеры', () => {
    expect(applyWrap('**мир**', 0, 7, '**', '**', 'текст').value).toBe('мир');
  });

  it('инлайн-код оборачивает в один обратный апостроф', () => {
    expect(applyWrap('x', 0, 1, '`', '`', 'код').value).toBe('`x`');
  });
});

describe('блок кода', () => {
  it('окружает содержимое ограждением из трёх апострофов', () => {
    expect(applyCodeBlock('code', 0, 4, '```', 'код')).toEqual({
      value: '```\ncode\n```',
      selectionStart: 4,
      selectionEnd: 8,
    });
  });

  it('без выделения подставляет плейсхолдер', () => {
    expect(applyCodeBlock('', 0, 0, '```', 'код').value).toBe('```\nкод\n```');
  });
});

describe('ссылка', () => {
  it('оборачивает выделение и ставит курсор на URL', () => {
    expect(applyLink('hello', 0, 5)).toEqual({
      value: '[hello](https://)',
      selectionStart: 8,
      selectionEnd: 16,
    });
  });

  it('без выделения вставляет заготовку и выделяет текст', () => {
    const result = applyLink('', 0, 0);
    expect(result.value).toBe('[текст](https://)');
    expect(result.value.slice(result.selectionStart, result.selectionEnd)).toBe('текст');
  });
});

describe('applyToolbarOp', () => {
  it('диспетчеризует операции по виду', () => {
    expect(applyToolbarOp({ kind: 'prefix', prefix: '# ' }, 'x', 0, 1).value).toBe('# x');
    expect(
      applyToolbarOp({ kind: 'wrap', before: '**', after: '**', placeholder: 'т' }, 'x', 0, 1).value,
    ).toBe('**x**');
    expect(
      applyToolbarOp({ kind: 'block', fence: '```', placeholder: 'к' }, '', 0, 0).value,
    ).toBe('```\nк\n```');
    expect(applyToolbarOp({ kind: 'link' }, 'x', 0, 1).value).toBe('[x](https://)');
  });
});
