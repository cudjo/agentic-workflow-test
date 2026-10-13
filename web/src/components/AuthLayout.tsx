/**
 * components/AuthLayout.tsx — каркас экранов `S1`/`S2` (DESIGN §2.11):
 * брендовая панель `.auth__aside` (скрыта ≤1024px) + центрированная карточка.
 */
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { SkipLink } from './SkipLink';

export interface AuthLayoutProps {
  quote: string;
  items: string[];
  skipHref: string;
  skipLabel: string;
  children: ReactNode;
}

export function AuthLayout({ quote, items, skipHref, skipLabel, children }: AuthLayoutProps) {
  return (
    <>
      <SkipLink href={skipHref}>{skipLabel}</SkipLink>
      <div className="auth">
        <aside className="auth__aside">
          <Link className="brand" to="/">
            <span className="brand__mark" aria-hidden="true">
              З
            </span>
            Заметки
          </Link>
          <div className="stack-6">
            <p className="auth__quote">{quote}</p>
            <ul className="auth__list">
              {items.map((item) => (
                <li key={item}>
                  <span aria-hidden="true">✓</span> {item}
                </li>
              ))}
            </ul>
          </div>
        </aside>
        <main className="auth__main">
          <div className="auth__card stack-6">{children}</div>
        </main>
      </div>
    </>
  );
}
