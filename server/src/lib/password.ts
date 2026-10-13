/**
 * lib/password.ts — хеширование паролей (PLAN §4.1).
 *
 * bcryptjs (чистый JS, без native-сборки — риск R2), cost 10.
 * Пароль никогда не попадает в ответы и логи (NFR-9/A9): здесь только hash/compare.
 */
import { compare, hash } from 'bcryptjs';

/** Стоимость bcrypt — по PLAN §4.1. */
export const BCRYPT_COST = 10;

/**
 * Хеш для фиктивного сравнения при неизвестном email — выравнивает время ответа,
 * не раскрывая существование пользователя (AC-5).
 */
export const DUMMY_PASSWORD_HASH =
  '$2b$10$Tx4ixcGuhvJ2Ncd7v8dIeefsAXgxAP6Q51U59sxUzvcNdcv/FbTU2';

/** Хеширует пароль (cost 10). */
export function hashPassword(password: string): Promise<string> {
  return hash(password, BCRYPT_COST);
}

/** Проверяет пароль против хеша. Не бросает — возвращает false при несовпадении. */
export function verifyPassword(password: string, passwordHash: string): Promise<boolean> {
  return compare(password, passwordHash);
}

/**
 * Постоянное по времени «вхолостую» сравнение — вызывается, когда пользователь не найден,
 * чтобы свести к минимуму разницу времени ответа между «нет email» и «неверный пароль».
 */
export async function fakeVerify(password: string): Promise<void> {
  await compare(password, DUMMY_PASSWORD_HASH);
}
