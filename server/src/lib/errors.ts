/**
 * lib/errors.ts — единый формат ошибок API (PLAN §3.2).
 *
 * Тело любой ошибки: `{ "error": { "code", "message", "field?" } }`.
 * `stack` и внутренние детали в ответ не попадают (NFR-9); серверная сторона логирует
 * исходную ошибку, но логгер редактирует секреты (см. app.ts).
 */

export type ErrorCode =
  | 'BAD_REQUEST'
  | 'VALIDATION_ERROR'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'RATE_LIMITED'
  | 'INTERNAL';

export interface ErrorBody {
  error: { code: string; message: string; field?: string };
}

/** Собирает тело ошибки в каноническом формате (field опускается, если не задан). */
export function errorBody(code: string, message: string, field?: string): ErrorBody {
  return field === undefined
    ? { error: { code, message } }
    : { error: { code, message, field } };
}

/** Доменная ошибка с HTTP-статусом и кодом — контракт для роутов/сервисов. */
export class AppError extends Error {
  readonly statusCode: number;
  readonly code: ErrorCode;
  readonly field?: string;

  constructor(
    statusCode: number,
    code: ErrorCode,
    message: string,
    options: { field?: string; cause?: unknown } = {},
  ) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.code = code;
    this.field = options.field;
  }

  toBody(): ErrorBody {
    return errorBody(this.code, this.message, this.field);
  }
}

const STATUS_CODES: Record<number, ErrorCode> = {
  400: 'BAD_REQUEST',
  401: 'UNAUTHORIZED',
  403: 'FORBIDDEN',
  404: 'NOT_FOUND',
  409: 'CONFLICT',
  422: 'VALIDATION_ERROR',
  429: 'RATE_LIMITED',
};

const DEFAULT_MESSAGES: Record<number, string> = {
  400: 'Некорректный запрос',
  401: 'Требуется авторизация',
  403: 'Доступ запрещён',
  404: 'Не найдено',
  409: 'Конфликт',
  422: 'Ошибка валидации',
  429: 'Слишком много запросов',
  500: 'Internal Server Error',
};

interface FastifyLikeError {
  statusCode?: number;
  message?: string;
}

/** Отображает любое исключение в пару (HTTP-статус, каноническое тело). */
export function toHttpError(error: unknown): { statusCode: number; body: ErrorBody } {
  if (error instanceof AppError) {
    return { statusCode: error.statusCode, body: error.toBody() };
  }

  const err = (error ?? {}) as FastifyLikeError;
  const rawStatus = typeof err.statusCode === 'number' ? err.statusCode : 500;

  if (rawStatus >= 500) {
    // Не раскрываем внутренние детали и stack (NFR-9).
    return { statusCode: 500, body: errorBody('INTERNAL', DEFAULT_MESSAGES[500]!) };
  }

  const statusCode = rawStatus >= 400 ? rawStatus : 400;
  const code = STATUS_CODES[statusCode] ?? 'BAD_REQUEST';
  const message =
    typeof err.message === 'string' && err.message.length > 0
      ? err.message
      : (DEFAULT_MESSAGES[statusCode] ?? 'Ошибка запроса');
  return { statusCode, body: errorBody(code, message) };
}
