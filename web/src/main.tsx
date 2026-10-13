import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AppRouter } from './router';
import './styles/tokens.css';
import './styles/base.css';
import './styles/glass.css';

const container = document.getElementById('root');
if (!container) throw new Error('Не найден элемент #root');
createRoot(container).render(
  <StrictMode>
    <AppRouter />
  </StrictMode>,
);
