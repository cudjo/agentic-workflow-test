/**
 * pages/Login.tsx — экран `S1` «Вход» (DESIGN §2.11).
 *
 * Состояния: пустая форма, валидация полей, обобщённая ошибка «Неверные
 * учётные данные» (AC-5), баннер rate-limit с таймером и блокировкой (AC-6),
 * баннер «Сессия истекла» при редиректе с защищённого экрана (AC-9).
 * После успеха — возврат на запрошенный URL или `/notes` (AC-4).
 */
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ApiError } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { Alert, type AlertVariant } from '../components/Alert';
import { AuthLayout } from '../components/AuthLayout';
import { ErrorIcon, SpinnerIcon } from '../components/icons';
import { formatCountdown } from '../lib/format';
import { validateEmail, validatePassword } from '../lib/validation';

interface FieldErrors {
  email?: string;
  password?: string;
}

interface Banner {
  variant: AlertVariant;
  title: string;
  body: string;
}

interface LocationState {
  from?: string;
  reason?: string;
}

export default function Login() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const state = (location.state as LocationState | null) ?? null;
  const target = state?.from && state.from !== '/login' ? state.from : '/notes';

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [errors, setErrors] = useState<FieldErrors>({});
  const [banner, setBanner] = useState<Banner | null>(
    state?.reason === 'expired'
      ? {
          variant: 'info',
          title: 'Сессия истекла',
          body: 'Мы вернули вас на вход. После входа снова откроется запрошенная страница.',
        }
      : null,
  );
  const [busy, setBusy] = useState(false);
  const [lockedUntil, setLockedUntil] = useState<number | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);
  const alertRef = useRef<HTMLDivElement>(null);

  const locked = lockedUntil !== null && lockedUntil > now;
  const remaining = locked && lockedUntil ? Math.max(0, Math.ceil((lockedUntil - now) / 1000)) : 0;

  // Тик раз в секунду для обратного отсчёта баннера rate-limit.
  useEffect(() => {
    if (lockedUntil === null) return;
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, [lockedUntil]);

  // По истечении окна — разблокируем форму и убираем предупреждение.
  useEffect(() => {
    if (lockedUntil !== null && lockedUntil <= now) {
      setLockedUntil(null);
      setBanner((current) => (current?.variant === 'warning' ? null : current));
    }
  }, [lockedUntil, now]);

  const activeBanner: Banner | null = locked
    ? {
        variant: 'warning',
        title: 'Слишком много попыток входа',
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
      await login(email.trim(), password);
      navigate(target, { replace: true });
    } catch (error) {
      if (error instanceof ApiError) {
        if (error.status === 401) {
          setBanner({
            variant: 'error',
            title: 'Неверные учётные данные',
            body: 'Проверьте email и пароль и попробуйте снова.',
          });
        } else if (error.status === 429) {
          const seconds = error.retryAfter && error.retryAfter > 0 ? error.retryAfter : 900;
          setNow(Date.now());
          setLockedUntil(Date.now() + seconds * 1000);
          setBanner(null);
        } else if (error.status === 422 && error.field) {
          setErrors((current) => ({ ...current, [error.field as keyof FieldErrors]: error.message }));
        } else {
          setBanner({ variant: 'error', title: 'Не удалось войти', body: error.message });
        }
      } else {
        setBanner({
          variant: 'error',
          title: 'Не удалось войти',
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
    if (emailError || passwordError) {
      setErrors({ email: emailError ?? undefined, password: passwordError ?? undefined });
      setBanner(null);
      (emailError ? emailRef : passwordRef).current?.focus();
      return;
    }

    setErrors({});
    setBanner(null);
    void submit();
  }

  return (
    <AuthLayout
      quote="Ваши заметки в markdown. Только ваши."
      items={[
        'Markdown с живым превью',
        'Теги, поиск и фильтры',
        'Плитки или список — как удобно',
      ]}
      skipHref="#login-form"
      skipLabel="Перейти к форме входа"
    >
      <div>
        <h1 style={{ marginBottom: 'var(--sp-2)' }}>Вход</h1>
        <p className="muted">Войдите, чтобы открыть свои заметки.</p>
      </div>

      {activeBanner ? (
        <Alert ref={alertRef} variant={activeBanner.variant} title={activeBanner.title} body={activeBanner.body} />
      ) : null}

      <form
        className="stack-4"
        id="login-form"
        noValidate
        onSubmit={handleSubmit}
        aria-describedby={locked ? 'login-locked-hint' : undefined}
      >
        <div className={`field${errors.email ? ' field--error' : ''}`}>
          <label className="field__label" htmlFor="login-email">
            Email <span className="field__req" aria-hidden="true">*</span>
          </label>
          <input
            ref={emailRef}
            id="login-email"
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
            aria-describedby={errors.email ? 'login-email-error' : undefined}
            onChange={(event) => setEmail(event.target.value)}
          />
          {errors.email ? (
            <span className="field__error" id="login-email-error" role="alert">
              <ErrorIcon />
              {errors.email}
            </span>
          ) : null}
        </div>

        <div className={`field${errors.password ? ' field--error' : ''}`}>
          <div className="row between">
            <label className="field__label" htmlFor="login-password">
              Пароль <span className="field__req" aria-hidden="true">*</span>
            </label>
            <a
              className="small"
              href="#"
              aria-disabled="true"
              title="Восстановление пароля вне MVP (Q-A8)"
              onClick={(event) => event.preventDefault()}
            >
              Забыли пароль?
            </a>
          </div>
          <input
            ref={passwordRef}
            id="login-password"
            name="password"
            className="input"
            type="password"
            autoComplete="current-password"
            value={password}
            required
            aria-required="true"
            disabled={locked}
            aria-invalid={errors.password ? true : undefined}
            aria-describedby={errors.password ? 'login-password-error' : 'login-password-hint'}
            onChange={(event) => setPassword(event.target.value)}
          />
          {errors.password ? (
            <span className="field__error" id="login-password-error" role="alert">
              <ErrorIcon />
              {errors.password}
            </span>
          ) : (
            <span className="field__hint" id="login-password-hint">
              Минимум 8 символов.
            </span>
          )}
        </div>

        <div className="checkline">
          <input type="checkbox" id="login-remember" name="remember" disabled={locked} />
          <label htmlFor="login-remember">Не выходить 7 дней на этом устройстве</label>
        </div>

        <button
          className="btn btn--primary btn--block"
          type="submit"
          disabled={locked || busy}
          aria-busy={busy}
        >
          {busy ? (
            <>
              <SpinnerIcon /> Вхожу…
            </>
          ) : (
            'Войти'
          )}
        </button>

        {locked ? (
          <p className="field__hint" id="login-locked-hint">
            Форма разблокируется автоматически по таймеру.
          </p>
        ) : null}
      </form>

      <p className="auth__foot">
        Нет аккаунта? <Link to="/register">Зарегистрироваться</Link>
      </p>
    </AuthLayout>
  );
}
