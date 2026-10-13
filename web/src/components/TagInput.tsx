/**
 * components/TagInput.tsx — поле тегов редактора (DESIGN §2.5/§2.12).
 *
 * Чипы-теги (`tag tag--removable`) с удаляющей кнопкой (`aria-label="Убрать тег «…»"`)
 * и «призрачным» инпутом внутри: Enter или запятая добавляют тег, пустые и
 * дубликаты (без учёта регистра) отбрасываются, лимиты — 20 тегов / 50 символов
 * с сообщением об ошибке. Подсказки — `datalist` из уже использованных тегов.
 */
import { useId, useState } from 'react';
import { CloseIcon, ErrorIcon } from './icons';

export const MAX_TAGS = 20;
export const MAX_TAG_LENGTH = 50;

const TOO_MANY_MESSAGE = 'Не больше 20 тегов';
const TOO_LONG_MESSAGE = 'Тег длиннее 50 символов';

const HINT = 'Enter или запятая — добавить. До 20 тегов, до 50 символов каждый, повторы и пустые не добавляются.';

interface AddResult {
  list: string[];
  error: string | null;
}

/** Добавляет тег к списку с проверкой лимитов/дублей (без изменения входа при ошибке). */
export function addTag(list: string[], raw: string): AddResult {
  const tag = raw.trim();
  if (!tag) return { list, error: null };
  if (tag.length > MAX_TAG_LENGTH) return { list, error: TOO_LONG_MESSAGE };
  if (list.some((value) => value.toLowerCase() === tag.toLowerCase())) {
    return { list, error: null };
  }
  if (list.length >= MAX_TAGS) return { list, error: TOO_MANY_MESSAGE };
  return { list: [...list, tag], error: null };
}

export interface TagInputProps {
  tags: string[];
  suggestions: string[];
  onChange: (tags: string[]) => void;
  disabled?: boolean;
}

export function TagInput({ tags, suggestions, onChange, disabled = false }: TagInputProps) {
  const [value, setValue] = useState('');
  const [error, setError] = useState<string | null>(null);

  const inputId = useId();
  const listId = useId();
  const hintId = useId();
  const errorId = useId();

  function commit(raw: string): void {
    const result = addTag(tags, raw);
    if (result.list !== tags) onChange(result.list);
    setValue('');
    setError(result.error);
  }

  function handleChange(event: React.ChangeEvent<HTMLInputElement>): void {
    const raw = event.target.value;
    if (/[,，]/.test(raw)) {
      const parts = raw.split(/[,，]/);
      const rest = parts.pop() ?? '';
      let next = tags;
      let nextError: string | null = null;
      for (const part of parts) {
        const result = addTag(next, part);
        next = result.list;
        if (result.error) nextError = result.error;
      }
      if (next !== tags) onChange(next);
      setValue(rest);
      setError(nextError);
      return;
    }
    setValue(raw);
    if (error) setError(null);
  }

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>): void {
    if (event.key === 'Enter') {
      event.preventDefault();
      commit(value);
    } else if (event.key === 'Backspace' && value === '' && tags.length > 0) {
      onChange(tags.slice(0, -1));
    }
  }

  function removeAt(index: number): void {
    onChange(tags.filter((_, i) => i !== index));
  }

  const describedBy = error ? `${hintId} ${errorId}` : hintId;

  return (
    <div className={`field${error ? ' field--error' : ''}`}>
      <label className="field__label" htmlFor={inputId}>
        Теги
      </label>
      <div
        className="input row wrap"
        style={{ gap: 'var(--sp-2)', minHeight: 48, padding: 'var(--sp-2) var(--sp-3)' }}
      >
        {tags.map((tag, index) => (
          <span className="tag tag--removable" key={`${tag}-${index}`}>
            <span className="tag__label">{tag}</span>
            <button
              className="tag__remove"
              type="button"
              aria-label={`Убрать тег «${tag}»`}
              onClick={() => removeAt(index)}
              disabled={disabled}
            >
              <CloseIcon size={12} />
            </button>
          </span>
        ))}
        <input
          id={inputId}
          className="tag-input__field"
          type="text"
          list={listId}
          value={value}
          placeholder="Добавить тег…"
          onChange={handleChange}
          onKeyDown={handleKeyDown}
          aria-describedby={describedBy}
          aria-invalid={error ? true : undefined}
          disabled={disabled}
          autoComplete="off"
          style={{
            border: 0,
            outlineOffset: 2,
            flex: '1 1 120px',
            minWidth: 120,
            padding: 'var(--sp-1)',
            fontSize: 'var(--fs-16)',
            fontFamily: 'inherit',
            background: 'transparent',
          }}
        />
        <datalist id={listId}>
          {suggestions.map((name) => (
            <option key={name} value={name} />
          ))}
        </datalist>
      </div>
      <span className="field__hint" id={hintId}>
        {HINT}
      </span>
      {error ? (
        <p className="field__error" id={errorId} role="alert">
          <ErrorIcon size={14} />
          {error}
        </p>
      ) : null}
    </div>
  );
}
