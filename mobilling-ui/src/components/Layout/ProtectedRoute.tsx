import { Navigate, useLocation } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

interface Props {
  children: React.ReactNode;
  requiredRole?: 'super_admin' | 'admin' | 'user';
  allowExpired?: boolean;
}

export default function ProtectedRoute({ children, requiredRole, allowExpired }: Props) {
  const { user, loading, hasAccess } = useAuth();
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

  // Subscription check for non-admin users (skip if allowExpired or on subscription paths)
  if (
    !allowExpired &&
    user.role !== 'super_admin' &&
    !hasAccess &&
    !location.pathname.startsWith('/subscription')
  ) {
    return <Navigate to="/subscription/expired" replace />;
  }

  return <>{children}</>;
}
