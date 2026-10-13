import '@testing-library/jest-dom/vitest';
import { afterEach, vi } from 'vitest';
import { cleanup } from '@testing-library/react';

/**
 * jsdom под Node 26 не предоставляет `localStorage` (глобальный `localStorage`
 * из Node доступен только с флагом `--localstorage-file`). Для тестов, которым
 * нужен `localStorage["notes.view"]` (T-08), подкладываем минимальную реализацию
 * `Storage` поверх `Map`, если она отсутствует. В браузере используется родная.
 */
function ensureLocalStorage(): void {
  const existing = (globalThis as { localStorage?: Storage }).localStorage;
  if (existing) return;

  const store = new Map<string, string>();
  const storage: Storage = {
    get length() {
      return store.size;
    },
    clear: () => store.clear(),
    getItem: (key: string) => (store.has(key) ? (store.get(key) as string) : null),
    key: (index: number) => Array.from(store.keys())[index] ?? null,
    removeItem: (key: string) => {
      store.delete(key);
    },
    setItem: (key: string, value: string) => {
      store.set(key, String(value));
    },
  };

  Object.defineProperty(globalThis, 'localStorage', {
    value: storage,
    configurable: true,
    writable: true,
  });
  if (typeof window !== 'undefined' && window !== (globalThis as unknown as Window)) {
    Object.defineProperty(window, 'localStorage', {
      value: storage,
      configurable: true,
      writable: true,
    });
  }
}

ensureLocalStorage();

afterEach(() => {
  cleanup();
  // Чистим cookie и localStorage между тестами (хранилище общее для файла).
  for (const part of document.cookie.split(';')) {
    const name = part.split('=')[0]?.trim();
    if (name) document.cookie = `${name}=; Max-Age=0; path=/`;
  }
  try {
    globalThis.localStorage?.clear();
  } catch {
    /* storage может быть недоступен */
  }
  vi.unstubAllGlobals();
});
