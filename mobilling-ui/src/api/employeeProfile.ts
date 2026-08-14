import api from './axios';

export interface EmployeeProfile {
  id: string;
  user_id: string;
  employee_number: string | null;
  hire_date: string | null;
  department: string | null;
  position: string | null;
  employment_type: 'full_time' | 'part_time' | 'contract' | 'intern' | null;
  national_id: string | null;
  nssf_number: string | null;
  tin_number: string | null;
  date_of_birth: string | null;
  gender: string | null;
  next_of_kin_name: string | null;
  next_of_kin_phone: string | null;
  bank_name: string | null;
  bank_branch: string | null;
  bank_account_name: string | null;
  bank_account_number: string | null;
  mobile_money_provider: string | null;
  mobile_money_number: string | null;
  termination_date: string | null;
  notes: string | null;
}

export interface EmployeeProfileFormData {
  employee_number?: string;
  hire_date?: string;
  department?: string;
  position?: string;
  employment_type?: 'full_time' | 'part_time' | 'contract' | 'intern';
  national_id?: string;
  nssf_number?: string;
  tin_number?: string;
  date_of_birth?: string;
  gender?: string;
  next_of_kin_name?: string;
  next_of_kin_phone?: string;
  bank_name?: string;
  bank_branch?: string;
  bank_account_name?: string;
  bank_account_number?: string;
  mobile_money_provider?: string;
  mobile_money_number?: string;
  termination_date?: string;
  notes?: string;
}

export interface EmployeeUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role?: { id: string; name: string; label: string } | null;
  supervisor?: { id: string; name: string } | null;
}

export const getEmployeeProfiles = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/employees', { params });

export const getEmployeeProfile = (userId: string) =>
  api.get<{ data: { user: EmployeeUser; profile: EmployeeProfile | null } }>(`/employees/${userId}`);

export const updateEmployeeProfile = (userId: string, data: EmployeeProfileFormData) =>
  api.put<{ data: EmployeeProfile }>(`/employees/${userId}`, data);

export const getMyEmployeeProfile = () =>
  api.get<{ data: { user: EmployeeUser; profile: EmployeeProfile | null } }>('/employees/mine');
