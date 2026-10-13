/**
 * components/Alert.tsx — алерт/баннер с корректной ролью для скринридера.
 *
 * Ошибки/warning — `role="alert"` + `aria-live="assertive"` (NFR-19);
 * success/info — `role="status"` + `aria-live="polite"`. Баннер фокусируемый
 * (`tabIndex={-1}`), чтобы перевести на него фокус при общей ошибке формы
 * (DESIGN §2.11).
 */
import { forwardRef } from 'react';
import { ErrorIcon, InfoIcon, SuccessIcon, WarningIcon } from './icons';

export type AlertVariant = 'error' | 'success' | 'warning' | 'info';

export interface AlertProps {
  variant: AlertVariant;
  title: string;
  body?: string;
}

const ICONS = {
  error: ErrorIcon,
  success: SuccessIcon,
  warning: WarningIcon,
  info: InfoIcon,
} as const;

export const Alert = forwardRef<HTMLDivElement, AlertProps>(function Alert(
  { variant, title, body },
  ref,
) {
  const role = variant === 'success' || variant === 'info' ? 'status' : 'alert';
  const Icon = ICONS[variant];
  return (
    <div
      className={`alert alert--${variant}`}
      role={role}
      aria-live={role === 'alert' ? 'assertive' : 'polite'}
      tabIndex={-1}
      ref={ref}
    >
      <span className="alert__icon">
        <Icon size={18} />
      </span>
      <div>
        <p className="alert__title">{title}</p>
        {body ? <p className="small">{body}</p> : null}
      </div>
    </div>
  );
});
