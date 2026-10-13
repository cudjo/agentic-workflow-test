/** components/AppLayout.tsx — каркас защищённых экранов: skip-link + Topbar + main. */
import { Outlet } from 'react-router-dom';
import { SkipLink } from './SkipLink';
import { Topbar } from './Topbar';

export function AppLayout() {
  return (
    <>
      <SkipLink href="#main-content">Перейти к заметкам</SkipLink>
      <Topbar />
      <main id="main-content" className="container page">
        <Outlet />
      </main>
    </>
  );
}
