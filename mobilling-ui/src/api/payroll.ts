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

export interface StatutoryRateSubscription {
  id: string;
  user_id: string;
  is_active: boolean;
  reference_number: string | null;
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
  user?: {
    id: string; name: string;
    employee_profile?: { tin_number: string | null; bank_name: string | null; bank_account_number: string | null } | null;
  };
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
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, StatutoryRateSubscription> } }>(`/statutory-rates/${id}/subscriptions`);
export const subscribeStatutoryRate = (id: string, data: { user_id: string; is_active?: boolean; reference_number?: string | null }) =>
  api.post<{ data: StatutoryRateSubscription }>(`/statutory-rates/${id}/subscriptions`, data);

// PAYE / attendance-penalty / late-report-penalty exemptions — same "Assign"
// shape as Statutory Rates, each backed by its own EmployeeProfile boolean
// flag (blanket on/off, not a percent-of-gross catalog row).
export const getPayeSubscriptions = () =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, { is_active: boolean }> } }>('/employees/paye-subscriptions');
export const subscribePaye = (data: { user_id: string; is_active?: boolean }) =>
  api.post<{ data: { is_active: boolean } }>('/employees/paye-subscriptions', data);

export const getAttendancePenaltySubscriptions = () =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, { is_active: boolean }> } }>('/employees/attendance-penalty-subscriptions');
export const subscribeAttendancePenalty = (data: { user_id: string; is_active?: boolean }) =>
  api.post<{ data: { is_active: boolean } }>('/employees/attendance-penalty-subscriptions', data);

export const getReportPenaltySubscriptions = () =>
  api.get<{ data: { users: { id: string; name: string }[]; subscriptions: Record<string, { is_active: boolean }> } }>('/employees/report-penalty-subscriptions');
export const subscribeReportPenalty = (data: { user_id: string; is_active?: boolean }) =>
  api.post<{ data: { is_active: boolean } }>('/employees/report-penalty-subscriptions', data);

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
export const deletePayrollRun = (id: string) => api.delete(`/payroll-runs/${id}`);

// Payslips
export const getPayslip = (id: string) => api.get<{ data: Payslip }>(`/payslips/${id}`);
export const downloadPayslipPdf = (id: string) => api.get(`/payslips/${id}/pdf`, { responseType: 'blob' });
export const getMyPayslips = () => api.get<{ data: Payslip[] }>('/payslips/mine');
export const downloadMyPayslipPdf = (id: string) => api.get(`/payslips/mine/${id}/pdf`, { responseType: 'blob' });

// Loans & Salary Advances
export interface Loan {
  id: string;
  user_id: string;
  principal: number;
  balance: number;
  monthly_installment: number;
  issued_date: string;
  status: 'active' | 'paid_off' | 'cancelled';
  notes: string | null;
  user?: { id: string; name: string };
}

export interface LoanPayment {
  id: string;
  loan_id: string;
  payroll_run_id: string | null;
  amount: number;
  balance_after: number;
  notes: string | null;
  created_at: string;
  payroll_run?: { id: string; month_key: string } | null;
}

export interface SalaryAdvance {
  id: string;
  user_id: string;
  amount: number;
  issued_date: string;
  recovery_month_key: string;
  status: 'pending' | 'recovered' | 'cancelled';
  notes: string | null;
  user?: { id: string; name: string };
}

export const getLoans = (userId?: string) => api.get<{ data: Loan[] }>('/loans', { params: { user_id: userId } });
export const createLoan = (data: { user_id: string; principal: number; monthly_installment: number; issued_date: string; notes?: string }) =>
  api.post<{ data: Loan }>('/loans', data);
export const getLoanPayments = (id: string) => api.get<{ data: LoanPayment[] }>(`/loans/${id}/payments`);
export const cancelLoan = (id: string) => api.post<{ data: Loan }>(`/loans/${id}/cancel`);

export const getSalaryAdvances = (userId?: string) => api.get<{ data: SalaryAdvance[] }>('/salary-advances', { params: { user_id: userId } });
export const createSalaryAdvance = (data: { user_id: string; amount: number; issued_date: string; recovery_month_key: string; notes?: string }) =>
  api.post<{ data: SalaryAdvance }>('/salary-advances', data);
export const cancelSalaryAdvance = (id: string) => api.post<{ data: SalaryAdvance }>(`/salary-advances/${id}/cancel`);
