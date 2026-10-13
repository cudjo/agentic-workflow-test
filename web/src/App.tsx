/**
 * App.tsx — маршруты приложения.
 *
 * Guard: `/notes` (и будущие защищённые экраны) обёрнуты в `<ProtectedRoute>`.
 * Неавторизованный → `/login` с сохранением целевого URL (DESIGN §1.2 поток G).
 */
import { Navigate, Route, Routes } from 'react-router-dom';
import { AppLayout } from './components/AppLayout';
import { ProtectedRoute } from './components/ProtectedRoute';
import Login from './pages/Login';
import NotFound from './pages/NotFound';
import Notes from './pages/Notes';
import Editor from './pages/Editor';
import Register from './pages/Register';

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />

      <Route element={<ProtectedRoute />}>
        <Route element={<AppLayout />}>
          <Route path="/notes" element={<Notes />} />
          <Route path="/notes/new" element={<Editor />} />
          <Route path="/notes/:id/edit" element={<Editor />} />
        </Route>
      </Route>

      <Route path="/" element={<Navigate to="/notes" replace />} />
      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
