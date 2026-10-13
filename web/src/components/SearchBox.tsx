/**
 * components/SearchBox.tsx — поиск по заметкам (DESIGN §2.4).
 *
 * Серверный поиск с debounce 300 ms (NFR-4): поле держит «черновой» текст и
 * сообщает наверх `onSearch` не чаще, чем раз в 300 ms после последнего ввода.
 * Видимой подписи нет — `sr-only` label; кнопка очистки появляется при
 * непустом тексте и возвращает фокус в поле (AC-43).
 */
import {
  forwardRef,
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
} from 'react';
import { CloseIcon, SearchIcon } from './icons';

export const SEARCH_DEBOUNCE_MS = 300;

interface SearchBoxProps {
  /** Актуальный запрос (используется для синхронизации при внешнем сбросе). */
  value: string;
  /** Вызывается с задержкой 300 ms после последнего ввода. */
  onSearch: (value: string) => void;
  /** id живого региона результатов (`aria-describedby`). */
  statusId?: string;
}

export const SearchBox = forwardRef<HTMLInputElement, SearchBoxProps>(
  function SearchBox({ value, onSearch, statusId }, ref) {
    const [text, setText] = useState(value);

    // Актуальный колбэк без перезапуска debounce-таймера.
    const onSearchRef = useRef(onSearch);
    useEffect(() => {
      onSearchRef.current = onSearch;
    });

    // Внешний сброс («Сбросить») — синхронизируем поле.
    useEffect(() => {
      setText(value);
    }, [value]);

    // Debounce: серверный запрос (NFR-4), не «дёргаем» список на каждый символ.
    useEffect(() => {
      if (text === value) return;
      const timer = window.setTimeout(() => onSearchRef.current(text), SEARCH_DEBOUNCE_MS);
      return () => window.clearTimeout(timer);
    }, [text, value]);

    function handleClear() {
      setText('');
      if (ref && typeof ref !== 'function') ref.current?.focus();
    }

    return (
      <div className="search">
        <SearchIcon className="search__icon" size={18} />
        <label className="sr-only" htmlFor="q">
          Поиск по заметкам
        </label>
        <input
          ref={ref}
          className="input"
          id="q"
          type="search"
          name="q"
          placeholder="Поиск по заголовку и тексту…"
          autoComplete="off"
          aria-describedby={statusId}
          data-search-input
          value={text}
          onChange={(event: ChangeEvent<HTMLInputElement>) => setText(event.target.value)}
        />
        <button
          className="search__clear"
          type="button"
          aria-label="Очистить поиск"
          data-search-clear
          hidden={text === ''}
          onClick={handleClear}
        >
          <CloseIcon size={16} />
        </button>
      </div>
    );
  },
);
