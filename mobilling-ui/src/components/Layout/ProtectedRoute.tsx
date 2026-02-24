import { Navigate, useLocation } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

interface Props {
  children: React.ReactNode;
  requiredRole?: 'super_admin' | 'admin' | 'user';
}

export default function ProtectedRoute({ children, requiredRole }: Props) {
  const { user, loading } = useAuth();
  const location = useLocation();

  if (loading) return <LoadingOverlay visible />;
  if (!user) return <Navigate to="/" replace />;

  // Role-based access control
  if (requiredRole === 'super_admin' && user.role !== 'super_admin') {
    return <Navigate to="/dashboard" replace />;
  }

  // Super admin should only access /admin/* paths
  if (user.role === 'super_admin' && !location.pathname.startsWith('/admin')) {
    return <Navigate to="/admin/tenants" replace />;
  }

  // Regular users cannot access /admin/* paths
  if (user.role !== 'super_admin' && location.pathname.startsWith('/admin')) {
    return <Navigate to="/dashboard" replace />;
  }

  return <>{children}</>;
}
