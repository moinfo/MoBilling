import { useAuth } from '../context/AuthContext';

export function usePermissions() {
  const { permissions } = useAuth();

  const permSet = new Set(permissions);
  const isSuperAdmin = permSet.has('*');

  const can = (permission: string): boolean => {
    if (isSuperAdmin) return true;
    return permSet.has(permission);
  };

  const canAny = (perms: string[]): boolean => {
    if (isSuperAdmin) return true;
    return perms.some((p) => permSet.has(p));
  };

  const canAll = (perms: string[]): boolean => {
    if (isSuperAdmin) return true;
    return perms.every((p) => permSet.has(p));
  };

  return { can, canAny, canAll, isSuperAdmin, permissions };
}
