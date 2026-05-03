import api from './axios';

export interface User {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: 'super_admin' | 'admin' | 'user';
  role_id: string | null;
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
    late_fee_enabled: boolean;
    late_fee_percent: number;
    late_fee_days: number;
  };
  // Client portal fields (only present when user_type === 'client')
  client_id?: string;
  client?: {
    id: string;
    name: string;
    email: string;
    phone: string | null;
    address: string | null;
    tax_id: string | null;
  };
}

export type UserType = 'tenant' | 'client';

export interface AuthResponse {
  user: User;
  token: string;
  user_type: UserType;
  permissions: string[];
  subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining?: number;
}

export interface MeResponse {
  user: User;
  user_type: UserType;
  permissions: string[];
  subscription_status?: 'trial' | 'subscribed' | 'expired' | 'deactivated';
  days_remaining?: number;
}

export interface LoginData {
  identifier: string;
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

export const forgotPassword = (identifier: string) =>
  api.post<{ message: string; email_hint?: string; requires_registration?: boolean }>('/auth/forgot-password', { identifier });

export const verifyResetOtp = (data: { identifier: string; otp: string }) =>
  api.post<{ message: string; requires_registration?: boolean; client_name?: string }>('/auth/verify-reset-otp', data);

export const resetPassword = (data: {
  identifier: string;
  otp: string;
  password: string;
  password_confirmation: string;
}) => api.post<AuthResponse & { message: string }>('/auth/reset-password', data);

// Portal self-registration
export interface OtpResponse {
  has_account: boolean;
  message: string;
  client_name?: string;
}

export const requestPortalOtp = (email: string) =>
  api.post<OtpResponse>('/portal/request-otp', { email });

export const verifyAndRegisterPortal = (data: {
  email: string;
  otp: string;
  name: string;
  password: string;
  password_confirmation: string;
  phone?: string;
}) => api.post<AuthResponse>('/portal/verify-register', data);
