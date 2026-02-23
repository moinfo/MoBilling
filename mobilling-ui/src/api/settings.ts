import api from './axios';
import { User } from './auth';

export interface CompanyData {
  name: string;
  email: string;
  phone?: string | null;
  address?: string | null;
  tax_id?: string | null;
  currency: string;
}

export interface ProfileData {
  name: string;
  email: string;
  phone?: string | null;
  current_password?: string;
  password?: string;
  password_confirmation?: string;
}

export const updateCompany = (data: CompanyData) =>
  api.put<{ tenant: User['tenant'] }>('/settings/company', data);

export const updateProfile = (data: ProfileData) =>
  api.put<{ user: User }>('/settings/profile', data);
