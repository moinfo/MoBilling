import api from './axios';

export interface User {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'super_admin' | 'admin' | 'user';
  is_active: boolean;
  tenant?: {
    id: string;
    name: string;
    email: string;
    phone: string | null;
    address: string | null;
    tax_id: string | null;
    currency: string;
    trial_ends_at: string | null;
    website: string | null;
    logo_url: string | null;
    logo_path: string | null;
    bank_name: string | null;
    bank_account_name: string | null;
    bank_account_number: string | null;
    bank_branch: string | null;
    payment_instructions: string | null;
  };
}

export interface AuthResponse {
  user: User;
  token: string;
  subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining?: number;
}

export interface MeResponse {
  user: User;
  subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining?: number;
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
  api.post<AuthResponse>('/auth/login', data);

export const register = (data: RegisterData) =>
  api.post<AuthResponse>('/auth/register', data);

export const logout = () => api.post('/auth/logout');

export const getMe = () =>
  api.get<MeResponse>('/auth/me');

export const forgotPassword = (email: string) =>
  api.post<{ message: string }>('/auth/forgot-password', { email });

export const resetPassword = (data: {
  token: string;
  email: string;
  password: string;
  password_confirmation: string;
}) => api.post<{ message: string }>('/auth/reset-password', data);
