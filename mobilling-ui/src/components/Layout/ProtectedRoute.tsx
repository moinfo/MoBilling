import { Navigate, useLocation } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

interface Props {
  children: React.ReactNode;
  requiredRole?: 'super_admin' | 'admin' | 'user';
  requiredUserType?: 'tenant' | 'client';
  allowExpired?: boolean;
}

export default function ProtectedRoute({ children, requiredRole, requiredUserType, allowExpired }: Props) {
  const { user, userType, loading, hasAccess } = useAuth();
  const location = useLocation();

  if (loading) return <LoadingOverlay visible />;
  if (!user) return <Navigate to="/" replace />;

  // User type routing
  if (requiredUserType === 'client' && userType !== 'client') {
    return <Navigate to="/dashboard" replace />;
  }
  if (requiredUserType === 'tenant' && userType === 'client') {
    return <Navigate to="/portal/dashboard" replace />;
  }

  // Client portal users can only access /portal/* paths
  if (userType === 'client' && !location.pathname.startsWith('/portal')) {
    return <Navigate to="/portal/dashboard" replace />;
  }

  // Tenant users should not access /portal/* paths
  if (userType === 'tenant' && location.pathname.startsWith('/portal')) {
    return <Navigate to="/dashboard" replace />;
  }

  // Role-based access control (tenant users only)
  if (requiredRole === 'super_admin' && user.role !== 'super_admin') {
    return <Navigate to="/dashboard" replace />;
  }

  // Super admin should only access /admin/* paths
  if (user.role === 'super_admin' && !location.pathname.startsWith('/admin')) {
    return <Navigate to="/admin/tenants" replace />;
  }

  // Regular users cannot access /admin/* paths
  if (userType === 'tenant' && user.role !== 'super_admin' && location.pathname.startsWith('/admin')) {
    return <Navigate to="/dashboard" replace />;
  }

  // Subscription check for non-admin users (skip if allowExpired or on subscription paths)
  if (
    !allowExpired &&
    userType === 'tenant' &&
    user.role !== 'super_admin' &&
    !hasAccess &&
    !location.pathname.startsWith('/subscription')
  ) {
    return <Navigate to="/subscription/expired" replace />;
  }

  return <>{children}</>;
}
