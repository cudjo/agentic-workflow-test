/**
 * lib/validation.ts — клиентская валидация auth-форм (DESIGN §2.11).
 *
 * Правила зеркалят серверные (PLAN §3.2): email-формат и пароль ≥ 8.
 * Сообщения — обязательные строки из DESIGN §2.11.
 */

/** Минимальная длина пароля (совпадает с серверной, PLAN §3.2). */
export const MIN_PASSWORD_LENGTH = 8;

/** Достаточно строгий формат — как на сервере (lib/validation.ts). */
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function validateEmail(value: string): string | null {
  const email = value.trim();
  if (email === '') return 'Укажите email.';
  if (!EMAIL_PATTERN.test(email)) {
    return 'Введите корректный email, например you@example.com.';
  }
  return null;
}

export function validatePassword(value: string): string | null {
  if (value === '') return 'Пароль обязателен.';
  if (value.length < MIN_PASSWORD_LENGTH) {
    return 'Слишком короткий пароль: нужно минимум 8 символов.';
  }
  return null;
}

export function validatePasswordConfirmation(password: string, confirmation: string): string | null {
  if (confirmation === '') return 'Повторите пароль.';
  if (password !== confirmation) return 'Пароли не совпадают.';
  return null;
}

export type PasswordTone = 'none' | 'weak' | 'mid' | 'strong';

export interface PasswordStrength {
  /** 0 — пусто, 1 — слабый, 2 — средний, 3 — надёжный. */
  level: 0 | 1 | 2 | 3;
  tone: PasswordTone;
  /** Текстовая оценка — дублирует цвет (a11y: не только цветом). */
  label: string;
}

const WEAK_LABEL = 'Слабый пароль — добавьте цифры и заглавные буквы';

/** Оценка силы пароля: длина + разнообразие классов символов (DESIGN §2.11). */
export function passwordStrength(value: string): PasswordStrength {
  if (value === '') return { level: 0, tone: 'none', label: '' };

  const classes = [/[a-zа-я]/, /[A-ZА-Я]/, /\d/, /[^A-Za-zА-Яа-я0-9]/].filter((re) =>
    re.test(value),
  ).length;

  if (value.length < MIN_PASSWORD_LENGTH) {
    return { level: 1, tone: 'weak', label: WEAK_LABEL };
  }
  if (value.length >= 12 && classes >= 3) {
    return { level: 3, tone: 'strong', label: 'Надёжный пароль.' };
  }
  if (classes >= 2) {
    return { level: 2, tone: 'mid', label: 'Средний пароль — добавьте цифры и символы.' };
  }
  return { level: 1, tone: 'weak', label: WEAK_LABEL };
}
