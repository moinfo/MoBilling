import api from './axios';

export interface TenantUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'admin' | 'user';
  is_active: boolean;
  created_at: string;
}

export interface UserFormData {
  name: string;
  email: string;
  password?: string;
  phone: string;
  role: 'admin' | 'user';
}

export const getUsers = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/users', { params });

export const createUser = (data: UserFormData) =>
  api.post('/users', data);

export const updateUser = (id: string, data: UserFormData) =>
  api.put(`/users/${id}`, data);

export const toggleUserActive = (id: string) =>
  api.patch(`/users/${id}/toggle-active`);
