import api from './axios';
import type { GroupedPermissions } from './roles';

export const getAllPermissions = () =>
  api.get<{ data: GroupedPermissions }>('/admin/permissions');

export const getTenantPermissions = (tenantId: string) =>
  api.get<{ data: string[] }>(`/admin/tenants/${tenantId}/permissions`);

export const updateTenantPermissions = (tenantId: string, permissionIds: string[]) =>
  api.put(`/admin/tenants/${tenantId}/permissions`, { permission_ids: permissionIds });
