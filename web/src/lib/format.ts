/** lib/format.ts — форматирование значений для UI. */

/** Секунды → «mm:ss» (таймер баннера rate-limit, DESIGN §4.2.6). */
export function formatCountdown(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

const MONTHS_SHORT = [
  'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

/** ISO-дата → «13 окт, 09:20» (карточки/строки списка, DESIGN §2.1/§9). */
export function formatNoteDate(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  const day = date.getDate();
  const month = MONTHS_SHORT[date.getMonth()];
  const hh = String(date.getHours()).padStart(2, '0');
  const mm = String(date.getMinutes()).padStart(2, '0');
  return `${day} ${month}, ${hh}:${mm}`;
}

/** ISO-дата → «8 окт 2026, 20:15» (мета экрана просмотра S5, DESIGN §2.13/§9). */
export function formatNoteDateFull(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  const hh = String(date.getHours()).padStart(2, '0');
  const mm = String(date.getMinutes()).padStart(2, '0');
  return `${date.getDate()} ${MONTHS_SHORT[date.getMonth()]} ${date.getFullYear()}, ${hh}:${mm}`;
}

/** ISO-дата → «1 окт 2026» (только дата, без времени — мета S5). */
export function formatNoteDateOnly(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '';
  return `${date.getDate()} ${MONTHS_SHORT[date.getMonth()]} ${date.getFullYear()}`;
}

/** Число → «1 284 символа» (группировка разрядов + русское склонение, мета S5). */
export function formatCharsCount(count: number): string {
  const grouped = String(count).replace(/\B(?=(\d{3})+(?!\d))/g, '\u00a0');
  const abs = Math.abs(count) % 100;
  const last = abs % 10;
  let word = 'символов';
  if (abs < 11 || abs > 19) {
    if (last === 1) word = 'символ';
    else if (last >= 2 && last <= 4) word = 'символа';
  }
  return `${grouped} ${word}`;
}

/**
 * Склонение «N заметок» (DESIGN §2.6): 1 заметка / 2–4 заметки / 5+ заметок.
 */
export function formatNotesCount(count: number): string {
  const abs = Math.abs(count) % 100;
  const last = abs % 10;
  if (abs > 10 && abs < 20) return `${count} заметок`;
  if (last === 1) return `${count} заметка`;
  if (last >= 2 && last <= 4) return `${count} заметки`;
  return `${count} заметок`;
}
