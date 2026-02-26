import api from './axios';

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
}

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
}) => api.post('/followups', data);

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

export const getClientFollowups = (clientId: string) =>
  api.get(`/followups/client/${clientId}`);
