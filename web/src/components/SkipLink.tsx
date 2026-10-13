/** components/SkipLink.tsx — skip-link, первый элемент в tab-порядке (DESIGN §5.4). */
import type { ReactNode } from 'react';

export function SkipLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a className="skip-link" href={href}>
      {children}
    </a>
  );
}
