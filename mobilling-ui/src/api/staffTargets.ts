import api from './axios';

export type CriterionType  = 'customer_count' | 'revenue' | 'item_sales' | 'custom';
export type CommissionType = 'none' | 'fixed' | 'percentage';
export type TargetStatus   = 'active' | 'self_reported' | 'verified' | 'cancelled';

export interface TargetCriterion {
  id:                string;
  type:              CriterionType;
  label:             string;
  unit:              string;
  goal_value:        number;
  achieved_value:    number | null;
  verified_value:    number | null;
  goal_met:          boolean | null;
  commission_type:   CommissionType;
  commission_value:  number | null;
  commission_earned: number | null;
}

export interface StaffTarget {
  id:               string;
  user:             { id: string; name: string };
  assigned_by:      { id: string; name: string };
  title:            string;
  description:      string | null;
  period_start:     string;
  period_end:       string;
  status:           TargetStatus;
  supervisor_notes: string | null;
  verified_by:      { id: string; name: string } | null;
  verified_at:      string | null;
  // Group bonus
  group_commission_type:   CommissionType;
  group_commission_value:  number | null;
  group_commission_earned: number | null;
  all_goals_met:           boolean | null;
  // Salary & penalty
  staff_salary:            number | null;
  deduct_on_failure:       boolean;
  salary_deduction_earned: number | null;
  // Manager (team-lead override)
  manager:                  { id: string; name: string } | null;
  manager_commission_type:  CommissionType;
  manager_commission_value: number | null;
  manager_commission_earned: number | null;
  // Totals
  gross_commission:  number;
  total_commission:  number;
  criteria:          TargetCriterion[];
  created_at:        string;
}

export interface CommissionSummaryEntry {
  user:              { id: string; name: string };
  gross_commission:  number;
  salary_deductions: number;
  total_commission:  number;
  manager_commission: number;
  targets_count:     number;
  targets:           {
    id: string; title: string; period: string;
    commission_earned: number;
    salary_deduction:  number;
  }[];
  managed_targets:   {
    id: string; title: string; period: string;
    staff: { id: string; name: string };
    commission_earned: number;
  }[];
}

export const getTargets = (params?: { user_id?: string; status?: string; managed_only?: boolean }) =>
  api.get<{ data: StaffTarget[] }>('/staff-targets', { params });

export const createTarget = (data: {
  user_id: string; title: string; description?: string;
  period_start: string; period_end: string;
  group_commission_type?: CommissionType; group_commission_value?: number;
  staff_salary?: number; deduct_on_failure?: boolean;
  manager_id?: string | null;
  manager_commission_type?: CommissionType;
  manager_commission_value?: number;
  criteria: {
    type: CriterionType; label: string; unit?: string; goal_value: number;
    commission_type: CommissionType; commission_value?: number;
  }[];
}) => api.post<{ data: StaffTarget }>('/staff-targets', data);

export const updateTarget = (id: string, data: {
  title?: string; description?: string;
  period_start?: string; period_end?: string;
  group_commission_type?: CommissionType; group_commission_value?: number;
  staff_salary?: number; deduct_on_failure?: boolean;
  manager_id?: string | null;
  manager_commission_type?: CommissionType;
  manager_commission_value?: number;
  criteria?: {
    type: CriterionType; label: string; unit?: string; goal_value: number;
    commission_type: CommissionType; commission_value?: number;
  }[];
}) => api.put<{ data: StaffTarget }>(`/staff-targets/${id}`, data);

export const deleteTarget = (id: string) =>
  api.delete(`/staff-targets/${id}`);

export const selfReportTarget = (id: string, data: {
  criteria: { id: string; achieved_value: number }[];
}) => api.post<{ data: StaffTarget }>(`/staff-targets/${id}/self-report`, data);

export const verifyTarget = (id: string, data: {
  criteria: { id: string; verified_value: number }[];
  supervisor_notes?: string;
}) => api.post<{ data: StaffTarget }>(`/staff-targets/${id}/verify`, data);

export const getCommissionSummary = (params?: { user_id?: string }) =>
  api.get<{ data: CommissionSummaryEntry[] }>('/staff-targets/summary', { params });
