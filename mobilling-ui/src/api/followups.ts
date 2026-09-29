import api from './axios';

export type CommissionType = 'none' | 'percentage' | 'fixed';

export interface AssignmentBrief {
  id: string;
  status: 'active' | 'completed' | 'cancelled';
  target: number;
  collected: number;
  remaining: number;
  commission_earned: number;
  achieved: boolean;
  commission_type: CommissionType;
  commission_value: number;
  paid_out_at: string | null;
}

export interface CommissionFields {
  target_amount?: number;
  commission_type?: CommissionType;
  commission_value?: number;
}

export interface FollowupEntry {
  id: string;
  document_id: string;
  document_number: string | null;
  client_id: string;
  client_name: string | null;
  client_phone: string | null;
  invoice_total: number;
  invoice_balance: number;
  assigned_to: string | null;
  user_id: string | null;
  call_date: string | null;
  outcome: 'promised' | 'declined' | 'no_answer' | 'disputed' | 'partial_payment' | null;
  notes: string | null;
  promise_date: string | null;
  promise_amount: number | null;
  next_followup: string | null;
  status: 'pending' | 'open' | 'fulfilled' | 'broken' | 'escalated' | 'cancelled';
  call_count?: number;
  created_at?: string;
  assignment?: AssignmentBrief | null;
}

export interface FollowupSummary {
  document_id: string;
  has_followup: boolean;
  /** The active (pending/open/broken) follow-up to log a call against — null if none active. */
  followup_id: string | null;
  assigned_to: string | null;
  /** Raw user id of the ACTIVE row's assignee — what a Reassign control prefills/compares against. */
  assigned_user_id?: string | null;
  last_outcome: FollowupEntry['outcome'];
  last_call_date: string | null;
  last_notes: string | null;
  next_followup: string | null;
  next_followup_overdue: boolean;
  status: FollowupEntry['status'] | null;
  call_count: number;
}

/** Batch "at a glance" follow-up info for a page of invoices — powers the Invoices list column. */
export const getFollowupSummary = (documentIds: string[]) =>
  api.post<{ data: FollowupSummary[] }>('/followups/summary', { document_ids: documentIds });

export interface StaffPerformanceRow {
  user_id: string;
  user_name: string | null;
  calls_logged: number;
  on_time: number;
  late: number;
  on_time_pct: number | null;
  avg_days_late: number | null;
  still_overdue: number;
}

export const getStaffPerformance = (params?: { date_from?: string; date_to?: string }) =>
  api.get<{ data: StaffPerformanceRow[] }>('/followups/staff-performance', { params });

export interface FollowupDashboard {
  due_today: FollowupEntry[];
  overdue_followups: FollowupEntry[];
  stats: {
    due_today: number;
    overdue: number;
    total_active: number;
  };
}

export const getFollowupDashboard = () =>
  api.get<{ data: FollowupDashboard }>('/followups/dashboard');

export const getFollowups = (params?: Record<string, string>) =>
  api.get('/followups', { params });

export const createFollowup = (data: {
  document_id: string;
  next_followup: string;
  user_id?: string;
  notes?: string;
} & CommissionFields) => api.post('/followups', data);

export const logCall = (
  followupId: string,
  data: {
    outcome: string;
    notes: string;
    promise_date?: string;
    promise_amount?: number;
    next_followup_override?: string;
  },
) => api.post(`/followups/${followupId}/log-call`, data);

export const cancelFollowup = (followupId: string) =>
  api.patch(`/followups/${followupId}/cancel`);

/** Change who is working an invoice's active follow-up (admin action; gated by documents.approve_collection). */
export const reassignFollowup = (followupId: string, userId: string, notes?: string) =>
  api.patch<{ data: FollowupEntry; message: string }>(`/followups/${followupId}/reassign`, { user_id: userId, notes });

export interface ClientFollowupHistoryEntry {
  id: string;
  document_id: string;
  document_number: string | null;
  assigned_to: string | null;
  call_date: string | null;
  outcome: FollowupEntry['outcome'];
  notes: string | null;
  promise_date: string | null;
  promise_amount: number | null;
  next_followup: string | null;
  status: FollowupEntry['status'];
  created_at: string;
}

export const getClientFollowups = (clientId: string) =>
  api.get<{ data: ClientFollowupHistoryEntry[] }>(`/followups/client/${clientId}`);

export interface UnassignedInvoice {
  id: string;
  document_number: string;
  client_id: string;
  client_name: string | null;
  client_phone: string | null;
  total: number;
  paid: number;
  balance_due: number;
  due_date: string | null;
  days_overdue: number;
  status: string;
  collection_reviewed_at: string | null;
  collection_reviewed_by_name: string | null;
  escalated: boolean;
  call_count: number;
}

export interface UnassignedResponse {
  data: UnassignedInvoice[];
  current_page: number;
  last_page: number;
  total: number;
  summary: { total: number; total_balance: number; not_reviewed: number };
}

export interface BulkSkipped {
  document_id: string;
  document_number: string | null;
  reason: string;
}

export interface BulkAssignResult {
  assigned: string[];
  skipped: BulkSkipped[];
  message: string;
}

export const getUnassignedInvoices = (params?: Record<string, string>) =>
  api.get<UnassignedResponse>('/followups/unassigned', { params });

export const bulkAssignFollowups = (data: {
  document_ids: string[];
  user_id: string;
  next_followup: string;
  notes?: string;
  commission_type?: CommissionType;
  commission_value?: number;
  targets?: Record<string, number>;
}) => api.post<BulkAssignResult>('/followups/bulk-assign', data);

export interface CollectionAssignmentRow extends AssignmentBrief {
  document_id: string;
  document_number: string | null;
  client_name: string | null;
  invoice_balance: number | null;
  user_id: string;
  user_name: string | null;
  batch_id: string | null;
  created_at: string;
}

export interface CollectionAssignmentsResponse {
  data: CollectionAssignmentRow[];
  summary: { target: number; collected: number; commission_earned: number; commission_unpaid: number; count: number };
}

export const getCollectionAssignments = (params?: Record<string, string>) =>
  api.get<CollectionAssignmentsResponse>('/collection-assignments', { params });

export const markCommissionPaid = (ids: string[]) =>
  api.post<{ message: string; updated: number }>('/collection-assignments/bulk-mark-paid', { ids });

/** Commission preview matching the backend formula (CollectionAssignment::commissionFor). */
export const previewCommission = (type: CommissionType, value: number, target: number, collected: number) => {
  const counted = Math.min(collected, target);
  if (type === 'percentage') return (counted * value) / 100;
  if (type === 'fixed') return target > 0 && collected >= target ? value : 0;
  return 0;
};
