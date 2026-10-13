/**
 * pages/Register.tsx — экран `S2` «Регистрация» (DESIGN §2.11).
 *
 * Поля: email, пароль (≥ 8), повтор пароля. Индикатор силы пароля
 * (3 сегмента + текстовая оценка — не только цветом). Дубликат email → 409
 * «Этот email уже зарегистрирован» (AC-2); успех → авто-авторизация и редирект
 * на `/notes` (AC-1).
 */
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { Alert, type AlertVariant } from '../components/Alert';
import { AuthLayout } from '../components/AuthLayout';
import { ErrorIcon, SpinnerIcon } from '../components/icons';
import { formatCountdown } from '../lib/format';
import {
  passwordStrength,
  validateEmail,
  validatePassword,
  validatePasswordConfirmation,
} from '../lib/validation';

interface FieldErrors {
  email?: string;
  password?: string;
  confirm?: string;
}

interface Banner {
  variant: AlertVariant;
  title: string;
  body: string;
}

const TONE_COLOR: Record<string, string> = {
  weak: 'var(--c-danger)',
  mid: '#b54708',
  strong: 'var(--c-success)',
};

export default function Register() {
  const { register } = useAuth();
  const navigate = useNavigate();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [errors, setErrors] = useState<FieldErrors>({});
  const [banner, setBanner] = useState<Banner | null>(null);
  const [busy, setBusy] = useState(false);
  const [lockedUntil, setLockedUntil] = useState<number | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const confirmRef = useRef<HTMLInputElement>(null);
  const alertRef = useRef<HTMLDivElement>(null);

  const locked = lockedUntil !== null && lockedUntil > now;
  const remaining = locked && lockedUntil ? Math.max(0, Math.ceil((lockedUntil - now) / 1000)) : 0;
  const strength = passwordStrength(password);

  useEffect(() => {
    if (lockedUntil === null) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [lockedUntil]);

  useEffect(() => {
    if (lockedUntil !== null && lockedUntil <= now) {
      setLockedUntil(null);
      setBanner((current) => (current?.variant === 'warning' ? null : current));
    }
  }, [lockedUntil, now]);

  const activeBanner: Banner | null = locked
    ? {
        variant: 'warning',
        title: 'Слишком много попыток регистрации',
        body: `Повторите через ${formatCountdown(remaining)}. Пароль не подбираем — просто ждём.`,
      }
    : banner;

  useEffect(() => {
    if (activeBanner && activeBanner.variant !== 'info') {
      alertRef.current?.focus();
    }
  }, [activeBanner]);

  async function submit(): Promise<void> {
    setBusy(true);
    try {
      await register(email.trim(), password);
      navigate('/notes', { replace: true });
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.status === 409) {
          setErrors((current) => ({ ...current, email: 'Уже используется.' }));
          setBanner({
            variant: 'error',
            title: 'Этот email уже зарегистрирован',
            body: 'Войдите в существующий аккаунт или укажите другой email.',
          });
        } else if (error.status === 429) {
          const seconds = error.retryAfter && error.retryAfter > 0 ? error.retryAfter : 900;
          setNow(Date.now());
          setLockedUntil(Date.now() + seconds * 1000);
          setBanner(null);
        } else if (error.status === 422 && error.field) {
          setErrors((current) => ({ ...current, [error.field as keyof FieldErrors]: error.message }));
        } else {
          setBanner({ variant: 'error', title: 'Не удалось создать аккаунт', body: error.message });
        }
      } else {
        setBanner({
          variant: 'error',
          title: 'Не удалось создать аккаунт',
          body: 'Нет соединения с сервером. Попробуйте ещё раз.',
        });
      }
    } finally {
      setBusy(false);
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>): void {
    event.preventDefault();
    if (locked || busy) return;

    const emailError = validateEmail(email);
    const passwordError = validatePassword(password);
    const confirmError = validatePasswordConfirmation(password, confirm);

    if (emailError || passwordError || confirmError) {
      setErrors({
        email: emailError ?? undefined,
        password: passwordError ?? undefined,
        confirm: confirmError ?? undefined,
      });
      setBanner(null);
      if (emailError) emailRef.current?.focus();
      else if (passwordError) passwordRef.current?.focus();
      else confirmRef.current?.focus();
      return;
    }

    setErrors({});
    setBanner(null);
    void submit();
  }

  return (
    <AuthLayout
      quote="Аккаунт за минуту — и заметки только у вас."
      items={[
        'Открытая регистрация, без подтверждения email',
        'Сразу попадаете в свои (пока пустые) заметки',
        'Пароль хранится только хешем',
      ]}
      skipHref="#register-form"
      skipLabel="Перейти к форме регистрации"
    >
      <div>
        <h1 style={{ marginBottom: 'var(--sp-2)' }}>Регистрация</h1>
        <p className="muted">Создайте аккаунт — заметки будут приватными по умолчанию.</p>
      </div>

      {activeBanner ? (
        <Alert ref={alertRef} variant={activeBanner.variant} title={activeBanner.title} body={activeBanner.body} />
      ) : null}

      <form
        className="stack-4"
        id="register-form"
        noValidate
        onSubmit={handleSubmit}
        aria-describedby={locked ? 'register-locked-hint' : undefined}
      >
        <div className={`field${errors.email ? ' field--error' : ''}`}>
          <label className="field__label" htmlFor="register-email">
            Email <span className="field__req" aria-hidden="true">*</span>
          </label>
          <input
            ref={emailRef}
            id="register-email"
            name="email"
            className="input"
            type="email"
            autoComplete="email"
            placeholder="you@example.com"
            value={email}
            required
            aria-required="true"
            disabled={locked}
            aria-invalid={errors.email ? true : undefined}
            aria-describedby={errors.email ? 'register-email-error' : 'register-email-hint'}
            onChange={(event) => setEmail(event.target.value)}
          />
          {errors.email ? (
            <span className="field__error" id="register-email-error" role="alert">
              <ErrorIcon />
              {errors.email}
            </span>
          ) : (
            <span className="field__hint" id="register-email-hint">
              По нему вы будете входить. Подтверждение email не требуется.
            </span>
          )}
        </div>

        <div className={`field${errors.password ? ' field--error' : ''}`}>
          <label className="field__label" htmlFor="register-password">
            Пароль <span className="field__req" aria-hidden="true">*</span>
          </label>
          <input
            ref={passwordRef}
            id="register-password"
            name="password"
            className="input"
            type="password"
            autoComplete="new-password"
            value={password}
            required
            aria-required="true"
            disabled={locked}
            aria-invalid={errors.password ? true : undefined}
            aria-describedby={errors.password ? 'register-password-error' : 'register-password-hint register-password-meter'}
            onChange={(event) => setPassword(event.target.value)}
          />
          {errors.password ? (
            <span className="field__error" id="register-password-error" role="alert">
              <ErrorIcon />
              {errors.password}
            </span>
          ) : (
            <span className="field__hint" id="register-password-hint">
              Минимум 8 символов.
            </span>
          )}
          {password ? (
            <div className="stack" style={{ gap: 'var(--sp-2)' }} id="register-password-meter">
              <div className="pw-meter" aria-hidden="true">
                {[0, 1, 2].map((index) => (
                  <span
                    key={index}
                    className={`pw-meter__seg${
                      index < strength.level ? ` pw-meter__seg--on-${strength.tone}` : ''
                    }`}
                  />
                ))}
              </div>
              <span className="tiny" style={{ color: TONE_COLOR[strength.tone] }}>
                {strength.label}
              </span>
            </div>
          ) : null}
        </div>

        <div className={`field${errors.confirm ? ' field--error' : ''}`}>
          <label className="field__label" htmlFor="register-confirm">
            Повторите пароль <span className="field__req" aria-hidden="true">*</span>
          </label>
          <input
            ref={confirmRef}
            id="register-confirm"
            name="password2"
            className="input"
            type="password"
            autoComplete="new-password"
            value={confirm}
            required
            aria-required="true"
            disabled={locked}
            aria-invalid={errors.confirm ? true : undefined}
            aria-describedby={errors.confirm ? 'register-confirm-error' : undefined}
            onChange={(event) => setConfirm(event.target.value)}
          />
          {errors.confirm ? (
            <span className="field__error" id="register-confirm-error" role="alert">
              <ErrorIcon />
              {errors.confirm}
            </span>
          ) : null}
        </div>

        <button
          className="btn btn--primary btn--block"
          type="submit"
          disabled={locked || busy}
          aria-busy={busy}
        >
          {busy ? (
            <>
              <SpinnerIcon /> Создаю аккаунт…
            </>
          ) : (
            'Создать аккаунт'
          )}
        </button>

        {locked ? (
          <p className="field__hint" id="register-locked-hint">
            Форма разблокируется автоматически по таймеру.
          </p>
        ) : null}
      </form>

      <p className="auth__foot">
        Уже есть аккаунт? <Link to="/login">Войти</Link>
      </p>
    </AuthLayout>
  );
}
