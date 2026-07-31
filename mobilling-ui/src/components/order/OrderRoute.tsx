import { Navigate, useLocation } from 'react-router-dom';
import { LoadingOverlay } from '@mantine/core';
import { useAuth } from '../../context/AuthContext';

/**
 * Guard for the /order/* storefront.
 *
 * Visitors arrive here straight from moinfo.co.tz with a plan already chosen,
 * so a bare redirect to "/" would silently throw that intent away. Instead we
 * carry the full path in ?next= and the login/register screens send the
 * customer back to the configured plan once they have an account.
 *
 * Ordering is client-only: the catalog is tenant-scoped off the authenticated
 * user, and staff have their own admin ordering flow.
 */
export default function OrderRoute({ children }: { children: React.ReactNode }) {
  const { user, userType, loading } = useAuth();
  const location = useLocation();

  if (loading) return <LoadingOverlay visible />;

  if (!user) {
    const next = encodeURIComponent(location.pathname + location.search);
    return <Navigate to={`/portal/login?next=${next}`} replace />;
  }

  // Staff who wander in get their own dashboard, not the client storefront.
  if (userType !== 'client') return <Navigate to="/dashboard" replace />;

  return <>{children}</>;
}
