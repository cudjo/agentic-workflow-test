/**
 * lib/view.ts — предпочтение вида «плитки/список» (DESIGN §2.3, PLAN §3.3).
 *
 * Хранится только на клиенте в `localStorage["notes.view"] ∈ {grid,list}`,
 * дефолт — `grid`. Повреждённое/отсутствующее значение трактуется как `grid`
 * (AC-25/AC-27). Доступ к `localStorage` защищён: в приватном режиме/SSR он
 * может бросать — тогда вид не сохраняется, но экран продолжает работать.
 */

export type ViewMode = 'grid' | 'list';

export const VIEW_STORAGE_KEY = 'notes.view';
export const DEFAULT_VIEW: ViewMode = 'grid';

export function loadView(): ViewMode {
  try {
    const raw = window.localStorage.getItem(VIEW_STORAGE_KEY);
    return raw === 'grid' || raw === 'list' ? raw : DEFAULT_VIEW;
  } catch {
    return DEFAULT_VIEW;
  }
}

export function saveView(view: ViewMode): void {
  try {
    window.localStorage.setItem(VIEW_STORAGE_KEY, view);
  } catch {
    /* носитель недоступен — деградация без падения */
  }
}
