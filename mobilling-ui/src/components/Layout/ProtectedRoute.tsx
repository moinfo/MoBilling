import { Navigate } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

export default function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();

  if (loading) return <LoadingOverlay visible />;
  if (!user) return <Navigate to="/" replace />;

  return <>{children}</>;
}
