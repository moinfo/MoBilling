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
}

export interface StatutoryRate {
  id: string;
  name: string;
  employee_percent: number;
  employer_percent: number;
  reduces_taxable_income: boolean;
  is_active: boolean;
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
  statutory_employee_total: number;
  statutory_employee_breakdown: { name: string; amount: number }[];
  taxable_income: number;
  paye_amount: number;
  other_deductions_total: number;
  deductions_breakdown: { name: string; amount: number }[];
  net_pay: number;
  statutory_employer_total: number;
  statutory_employer_breakdown: { name: string; amount: number }[];
  employer_cost_total: number;
  user?: { id: string; name: string };
  payroll_run?: { id: string; month_key: string; status: string };
}

// Settings (PAYE brackets only — NSSF/WCF/SDL/etc. live in the Statutory Rates catalog below)
export const getPayrollSettings = () => api.get<{ data: PayrollSettings }>('/payroll-settings');
export const updatePayrollSettings = (data: { paye_brackets: PayeBracket[] }) => api.put<{ data: PayrollSettings }>('/payroll-settings', data);

// Statutory Rates (tenant-configurable catalog: NSSF, WCF, SDL, NHIF, or anything else)
export const getStatutoryRates = () => api.get<{ data: StatutoryRate[] }>('/statutory-rates');
export const createStatutoryRate = (data: { name: string; employee_percent: number; employer_percent: number; reduces_taxable_income?: boolean }) =>
  api.post<{ data: StatutoryRate }>('/statutory-rates', data);
export const updateStatutoryRate = (id: string, data: { name: string; employee_percent: number; employer_percent: number; reduces_taxable_income?: boolean; is_active?: boolean }) =>
  api.put<{ data: StatutoryRate }>(`/statutory-rates/${id}`, data);
export const deleteStatutoryRate = (id: string) => api.delete(`/statutory-rates/${id}`);
export const getStatutoryRateSubscriptions = (id: string) =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, Subscription> } }>(`/statutory-rates/${id}/subscriptions`);
export const subscribeStatutoryRate = (id: string, data: { user_id: string; is_active?: boolean }) =>
  api.post<{ data: Subscription }>(`/statutory-rates/${id}/subscriptions`, data);

// PAYE exemptions — same "Assign" shape as Statutory Rates, backed by
// EmployeeProfile.subject_to_paye (PAYE is bracket-based, not a catalog row)
export const getPayeSubscriptions = () =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, { is_active: boolean }> } }>('/employees/paye-subscriptions');
export const subscribePaye = (data: { user_id: string; is_active?: boolean }) =>
  api.post<{ data: { is_active: boolean } }>('/employees/paye-subscriptions', data);

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
