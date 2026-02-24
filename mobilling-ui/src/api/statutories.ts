import api from './axios';
import { Bill } from './bills';

export interface Statutory {
  id: string;
  name: string;
  bill_category_id: string | null;
  bill_category: { id: string; name: string; parent_name: string | null } | null;
  amount: string;
  cycle: string;
  issue_date: string;
  next_due_date: string;
  remind_days_before: number;
  is_active: boolean;
  notes: string | null;
  created_at: string;
  // Computed (from schedule endpoint)
  status?: 'paid' | 'overdue' | 'due_soon' | 'upcoming';
  days_remaining?: number;
  paid_amount?: number;
  remaining_amount?: number;
  progress_percent?: number;
  current_bill?: Bill;
}

export interface StatutoryFormData {
  name: string;
  bill_category_id?: string | null;
  amount: number;
  cycle: string;
  issue_date: string;
  remind_days_before: number;
  is_active: boolean;
  notes: string;
}

export interface ScheduleResponse {
  stats: {
    total: number;
    overdue: number;
    due_soon: number;
    paid: number;
  };
  data: Statutory[];
}

export const getStatutories = (params?: { search?: string; page?: number }) =>
  api.get('/statutories', { params });

export const getStatutory = (id: string) =>
  api.get<{ data: Statutory }>(`/statutories/${id}`);

export const createStatutory = (data: StatutoryFormData) =>
  api.post('/statutories', data);

export const updateStatutory = (id: string, data: StatutoryFormData) =>
  api.put(`/statutories/${id}`, data);

export const deleteStatutory = (id: string) =>
  api.delete(`/statutories/${id}`);

export const getStatutorySchedule = () =>
  api.get<ScheduleResponse>('/statutory-schedule');
