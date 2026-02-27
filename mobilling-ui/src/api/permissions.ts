import api from './axios';
import type { GroupedPermissions } from './roles';

export const getAllPermissions = () =>
  api.get<{ data: GroupedPermissions }>('/admin/permissions');

export const getTenantPermissions = (tenantId: string) =>
  api.get<{ data: string[] }>(`/admin/tenants/${tenantId}/permissions`);

export const updateTenantPermissions = (tenantId: string, permissionIds: string[]) =>
  api.put(`/admin/tenants/${tenantId}/permissions`, { permission_ids: permissionIds });

export interface PermissionTenant {
  id: string;
  name: string;
  email: string;
  is_active: boolean;
  enabled: boolean;
}

export const getPermissionTenants = (permissionId: string) =>
  api.get<{ data: PermissionTenant[] }>(`/admin/permissions/${permissionId}/tenants`);

export const updatePermissionTenants = (permissionId: string, tenantIds: string[]) =>
  api.put<{ message: string }>(`/admin/permissions/${permissionId}/tenants`, { tenant_ids: tenantIds });

// --- Role Templates (Super Admin) ---

export interface RoleTemplate {
  type: string;
  label: string;
  description: string;
  permissions_count: number;
  total_permissions: number;
  tenants_count: number | null;
  editable: boolean;
}

export interface RoleTemplateDetail {
  type: string;
  grouped_permissions: GroupedPermissions;
  enabled_ids: string[];
}

export const getRoleTemplates = () =>
  api.get<{ data: RoleTemplate[] }>('/admin/role-templates');

export const getRoleTemplate = (type: string) =>
  api.get<{ data: RoleTemplateDetail }>(`/admin/role-templates/${type}`);

export const updateRoleTemplate = (type: string, permissionIds: string[]) =>
  api.put<{ message: string; tenants_updated: number }>(`/admin/role-templates/${type}`, { permission_ids: permissionIds });
