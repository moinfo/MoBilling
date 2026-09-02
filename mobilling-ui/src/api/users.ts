import api from './axios';

export interface TenantUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'admin' | 'user';
  role_id: string | null;
  role_name: string | null;
  is_active: boolean;
  created_at: string;
}

export interface UserFormData {
  name: string;
  email: string;
  password?: string;
  phone: string;
  role_id: string;
}

export const getUsers = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/users', { params });

export interface AssignableUser {
  id: string;
  name: string;
}

/** id+name only, for an "assign to" picker — works for any authenticated staff member, not just settings.users. */
export const getAssignableUsers = () =>
  api.get<{ data: AssignableUser[] }>('/users/assignable');

export const createUser = (data: UserFormData) =>
  api.post('/users', data);

export const updateUser = (id: string, data: UserFormData) =>
  api.put(`/users/${id}`, data);

export const toggleUserActive = (id: string) =>
  api.patch(`/users/${id}/toggle-active`);
