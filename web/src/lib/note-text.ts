/**
 * lib/note-text.ts — производные тексты заметки для карточки/строки (DESIGN §2.1).
 *
 * Фрагмент — **plain-text выжимка** исходного markdown (без рендера!): экран
 * списка не вставляет HTML и не санитайзит, просто показывает читаемый текст.
 * Заголовок для заметки без `title` берётся из первой непустой строки текста (E3).
 */
import type { Note } from '../api/notes';

/**
 * Грубо снимает markdown-разметку, оставляя обычный текст. Не претендует на
 * полноту парсера — нужен стабильный, безопасный (без HTML) фрагмент.
 */
export function toPlainText(markdown: string): string {
  if (!markdown) return '';

  let text = markdown;

  // Ограждённые блоки кода → их содержимое.
  text = text.replace(/```[^\n]*\n?([\s\S]*?)```/g, '$1');
  // Изображения ![alt](url) → alt.
  text = text.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  // Ссылки [text](url) → text.
  text = text.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1');
  // Заголовки.
  text = text.replace(/^[ \t]{0,3}#{1,6}[ \t]+/gm, '');
  // Цитаты.
  text = text.replace(/^[ \t]{0,3}>[ \t]?/gm, '');
  // Маркеры списков.
  text = text.replace(/^[ \t]{0,3}(?:[-*+]|\d+\.)[ \t]+/gm, '');
  // Горизонтальные линии.
  text = text.replace(/^[ \t]{0,3}(?:[-*_][ \t]*){3,}$/gm, '');
  // Инлайн-код.
  text = text.replace(/`([^`]*)`/g, '$1');
  // Жирный/курсив.
  text = text.replace(/(\*\*|__)(.*?)\1/g, '$2');
  text = text.replace(/(\*|_)(.*?)\1/g, '$2');

  return text.replace(/\s+/g, ' ').trim();
}

/** Заголовок заметки: `title` либо первая непустая строка текста (E3). */
export function noteTitle(note: Pick<Note, 'title' | 'bodyMarkdown'>): string {
  const explicit = note.title?.trim();
  if (explicit) return explicit;

  const firstLine =
    note.bodyMarkdown.split(/\r?\n/).find((line) => line.trim() !== '') ?? '';
  const derived = toPlainText(firstLine).trim();
  return derived || 'Без названия';
}
