import api from './axios';

export interface Permission {
  id: string;
  name: string;
  label: string;
  category: 'menu' | 'crud' | 'settings' | 'reports';
  group_name: string;
}

export interface Role {
  id: string;
  name: string;
  label: string;
  is_system: boolean;
  users_count: number;
  permissions: Pick<Permission, 'id' | 'name'>[];
}

export interface RoleFormData {
  name?: string;
  label: string;
  permissions: string[]; // permission IDs
}

// Grouped permissions: { category: { group_name: Permission[] } }
export type GroupedPermissions = Record<string, Record<string, Permission[]>>;

export const getRoles = () =>
  api.get<{ data: Role[] }>('/roles');

export const createRole = (data: RoleFormData) =>
  api.post<{ data: Role }>('/roles', data);

export const updateRole = (id: string, data: RoleFormData) =>
  api.put<{ data: Role }>(`/roles/${id}`, data);

export const deleteRole = (id: string) =>
  api.delete(`/roles/${id}`);

export const getAvailablePermissions = () =>
  api.get<{ data: GroupedPermissions }>('/available-permissions');
