import api from './axios';

export interface SatisfactionCallEntry {
  id: string;
  client_id: string;
  client_name: string | null;
  client_phone: string | null;
  user_id: string | null;
  assigned_to: string | null;
  scheduled_date: string;
  called_at: string | null;
  outcome: 'satisfied' | 'needs_improvement' | 'complaint' | 'suggestion' | 'no_answer' | 'unreachable' | null;
  rating: number | null;
  feedback: string | null;
  internal_notes: string | null;
  status: 'scheduled' | 'completed' | 'missed' | 'cancelled';
  month_key: string;
  created_at?: string;
}

export interface SatisfactionDashboard {
  due_today: SatisfactionCallEntry[];
  overdue: SatisfactionCallEntry[];
  stats: {
    due_today: number;
    overdue: number;
    completed_this_month: number;
    total_this_month: number;
    avg_rating: number | null;
  };
}

export const getSatisfactionDashboard = () =>
  api.get<{ data: SatisfactionDashboard }>('/satisfaction-calls/dashboard');

export const getSatisfactionCalls = (params?: Record<string, string>) =>
  api.get('/satisfaction-calls', { params });

export const logSatisfactionCall = (
  id: string,
  data: {
    outcome: string;
    rating?: number;
    feedback?: string;
    internal_notes?: string;
  },
) => api.post(`/satisfaction-calls/${id}/log-call`, data);

export const rescheduleSatisfactionCall = (
  id: string,
  data: { scheduled_date: string },
) => api.patch(`/satisfaction-calls/${id}/reschedule`, data);

export const cancelSatisfactionCall = (id: string) =>
  api.patch(`/satisfaction-calls/${id}/cancel`);

export const getClientSatisfactionHistory = (clientId: string) =>
  api.get(`/satisfaction-calls/client/${clientId}`);
