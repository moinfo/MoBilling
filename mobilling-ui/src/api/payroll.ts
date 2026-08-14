import api from './axios';

export interface PayeBracket {
  min: number;
  max: number | null;
  rate: number;
  base_deduction: number;
}

export interface PayrollSettings {
  id: string;
  paye_brackets: PayeBracket[];
  nssf_employee_percent: number;
  nssf_employer_percent: number;
  wcf_percent: number;
  sdl_percent: number;
}

export interface StaffSalary {
  id: string;
  user_id: string;
  basic_salary: number;
  effective_from: string;
  notes: string | null;
  user?: { id: string; name: string };
}

export interface Allowance {
  id: string;
  name: string;
  calculation_type: 'fixed' | 'percent_of_basic';
  default_amount: number;
  is_active: boolean;
}

export interface Deduction {
  id: string;
  name: string;
  calculation_type: 'fixed' | 'percent_of_basic';
  default_amount: number;
  is_active: boolean;
}

export interface Subscription {
  id: string;
  user_id: string;
  amount_override: number | null;
  is_active: boolean;
}

export interface PayrollRun {
  id: string;
  month_key: string;
  status: 'draft' | 'finalized';
  generated_at: string | null;
  finalized_at: string | null;
  payslips_count?: number;
  payslips?: Payslip[];
  generated_by?: { id: string; name: string } | null;
  finalized_by?: { id: string; name: string } | null;
}

export interface Payslip {
  id: string;
  payroll_run_id: string;
  user_id: string;
  basic_salary: number;
  allowances_total: number;
  allowances_breakdown: { name: string; amount: number }[];
  gross_pay: number;
  nssf_employee_amount: number;
  taxable_income: number;
  paye_amount: number;
  other_deductions_total: number;
  deductions_breakdown: { name: string; amount: number }[];
  net_pay: number;
  nssf_employer_amount: number;
  wcf_amount: number;
  sdl_amount: number;
  employer_cost_total: number;
  user?: { id: string; name: string };
  payroll_run?: { id: string; month_key: string; status: string };
}

// Settings
export const getPayrollSettings = () => api.get<{ data: PayrollSettings }>('/payroll-settings');
export const updatePayrollSettings = (data: Omit<PayrollSettings, 'id'>) => api.put<{ data: PayrollSettings }>('/payroll-settings', data);

// Staff Salaries
export const getStaffSalaries = (userId?: string) => api.get<{ data: StaffSalary[] }>('/staff-salaries', { params: { user_id: userId } });
export const createStaffSalary = (data: { user_id: string; basic_salary: number; effective_from: string; notes?: string }) =>
  api.post<{ data: StaffSalary }>('/staff-salaries', data);
export const deleteStaffSalary = (id: string) => api.delete(`/staff-salaries/${id}`);

// Allowances
export const getAllowances = () => api.get<{ data: Allowance[] }>('/allowances');
export const createAllowance = (data: { name: string; calculation_type: 'fixed' | 'percent_of_basic'; default_amount: number }) =>
  api.post<{ data: Allowance }>('/allowances', data);
export const updateAllowance = (id: string, data: { name: string; calculation_type: 'fixed' | 'percent_of_basic'; default_amount: number; is_active?: boolean }) =>
  api.put<{ data: Allowance }>(`/allowances/${id}`, data);
export const deleteAllowance = (id: string) => api.delete(`/allowances/${id}`);
export const getAllowanceSubscriptions = (id: string) =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, Subscription> } }>(`/allowances/${id}/subscriptions`);
export const subscribeAllowance = (id: string, data: { user_id: string; amount_override?: number | null; is_active?: boolean }) =>
  api.post<{ data: Subscription }>(`/allowances/${id}/subscriptions`, data);

// Deductions
export const getDeductions = () => api.get<{ data: Deduction[] }>('/deductions');
export const createDeduction = (data: { name: string; calculation_type: 'fixed' | 'percent_of_basic'; default_amount: number }) =>
  api.post<{ data: Deduction }>('/deductions', data);
export const updateDeduction = (id: string, data: { name: string; calculation_type: 'fixed' | 'percent_of_basic'; default_amount: number; is_active?: boolean }) =>
  api.put<{ data: Deduction }>(`/deductions/${id}`, data);
export const deleteDeduction = (id: string) => api.delete(`/deductions/${id}`);
export const getDeductionSubscriptions = (id: string) =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, Subscription> } }>(`/deductions/${id}/subscriptions`);
export const subscribeDeduction = (id: string, data: { user_id: string; amount_override?: number | null; is_active?: boolean }) =>
  api.post<{ data: Subscription }>(`/deductions/${id}/subscriptions`, data);

// Payroll Runs
export const getPayrollRuns = () => api.get<{ data: PayrollRun[] }>('/payroll-runs');
export const getPayrollRun = (id: string) => api.get<{ data: PayrollRun }>(`/payroll-runs/${id}`);
export const generatePayrollRun = (monthKey: string) => api.post<{ data: PayrollRun; message: string }>('/payroll-runs/generate', { month_key: monthKey });
export const finalizePayrollRun = (id: string) => api.post<{ data: PayrollRun }>(`/payroll-runs/${id}/finalize`);

// Payslips
export const getPayslip = (id: string) => api.get<{ data: Payslip }>(`/payslips/${id}`);
export const downloadPayslipPdf = (id: string) => api.get(`/payslips/${id}/pdf`, { responseType: 'blob' });
export const getMyPayslips = () => api.get<{ data: Payslip[] }>('/payslips/mine');
export const downloadMyPayslipPdf = (id: string) => api.get(`/payslips/mine/${id}/pdf`, { responseType: 'blob' });
