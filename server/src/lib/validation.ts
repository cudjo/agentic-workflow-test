/**
 * lib/validation.ts — валидация входных данных auth-эндпоинтов (PLAN §3.2, §4).
 *
 * Контракт ошибок: `AppError(422, 'VALIDATION_ERROR', message, { field })` — поле,
 * к которому относится ошибка, обязательно (AC-2/приёмка T-03: «422 с field»).
 *
 * Единая точка для правил: email-формат, пароль ≥ 8 символов.
 * Регистронезависимое сравнение email обеспечивает `normalizeEmail` + `COLLATE NOCASE` в схеме.
 */
import { AppError } from './errors.js';

/** Минимальная длина пароля (PLAN §3.2). */
export const MIN_PASSWORD_LENGTH = 8;
/** Верхняя граница — защита от DoS на bcrypt (bcrypt всё равно обрезает на 72 байтах). */
export const MAX_PASSWORD_LENGTH = 200;
/** RFC 5321 ограничивает практическую длину адреса. */
export const MAX_EMAIL_LENGTH = 254;

/** Достаточно строгий и предсказуемый формат: local@domain.tld без пробелов. */
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Приводит email к канонической форме: без внешних пробелов, в нижнем регистре. */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** Валидирует email и возвращает нормализованное значение. @throws AppError 422 field=email */
export function assertValidEmail(value: unknown): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new AppError(422, 'VALIDATION_ERROR', 'Укажите email', { field: 'email' });
  }
  const email = value.trim();
  if (email.length > MAX_EMAIL_LENGTH || !EMAIL_PATTERN.test(email)) {
    throw new AppError(422, 'VALIDATION_ERROR', 'Некорректный формат email', { field: 'email' });
  }
  return normalizeEmail(email);
}

/** Валидирует пароль и возвращает его как есть (пробелы значимы). @throws AppError 422 field=password */
export function assertValidPassword(value: unknown): string {
  if (typeof value !== 'string' || value.length < MIN_PASSWORD_LENGTH) {
    throw new AppError(
      422,
      'VALIDATION_ERROR',
      `Пароль должен содержать минимум ${MIN_PASSWORD_LENGTH} символов`,
      { field: 'password' },
    );
  }
  if (value.length > MAX_PASSWORD_LENGTH) {
    throw new AppError(
      422,
      'VALIDATION_ERROR',
      `Пароль не должен превышать ${MAX_PASSWORD_LENGTH} символов`,
      { field: 'password' },
    );
  }
  return value;
}

export interface Credentials {
  email: string;
  password: string;
}

/** Валидирует пару email+password (register). @throws AppError 422 с `field` */
export function assertValidCredentials(body: unknown): Credentials {
  const record = (body ?? {}) as Record<string, unknown>;
  const email = assertValidEmail(record.email);
  const password = assertValidPassword(record.password);
  return { email, password };
}
