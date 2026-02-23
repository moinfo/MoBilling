import api from './axios';

export interface User {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'admin' | 'user';
  is_active: boolean;
  tenant: {
    id: string;
    name: string;
    email: string;
    phone: string | null;
    address: string | null;
    tax_id: string | null;
    currency: string;
  };
}

export interface LoginData {
  email: string;
  password: string;
}

export interface RegisterData {
  company_name: string;
  name: string;
  email: string;
  password: string;
  password_confirmation: string;
  phone?: string;
}

export const login = (data: LoginData) =>
  api.post<{ user: User; token: string }>('/auth/login', data);

export const register = (data: RegisterData) =>
  api.post<{ user: User; token: string }>('/auth/register', data);

export const logout = () => api.post('/auth/logout');

export const getMe = () =>
  api.get<{ user: User }>('/auth/me');
