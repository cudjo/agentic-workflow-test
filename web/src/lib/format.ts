/** lib/format.ts — форматирование значений для UI. */

/** Секунды → «mm:ss» (таймер баннера rate-limit, DESIGN §4.2.6). */
export function formatCountdown(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}
