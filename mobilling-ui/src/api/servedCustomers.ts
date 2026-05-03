import api from './axios';

export interface ServedService {
  id:          string;
  name:        string;
  description: string | null;
  is_active:   boolean;
  sort_order:  number;
}

export interface CustomerFeedback {
  id:             string;
  called_at:      string;
  rating:         number | null;
  outcome:        'satisfied' | 'neutral' | 'dissatisfied' | null;
  feedback:       string | null;
  challenges:     string | null;
  internal_notes: string | null;
  created_by:     { id: string; name: string } | null;
}

export interface ServedCustomer {
  id:          string;
  name:        string;
  phone:       string | null;
  served_date: string;
  notes:       string | null;
  services:    { id: string; name: string }[];
  feedbacks:   CustomerFeedback[];
  created_at:  string;
  created_by:  { id: string; name: string } | null;
}

export const getServices = () =>
  api.get<{ data: ServedService[] }>('/served/services');

export const createService = (data: Partial<ServedService>) =>
  api.post<{ data: ServedService }>('/served/services', data);

export const updateService = (id: string, data: Partial<ServedService>) =>
  api.put<{ data: ServedService }>(`/served/services/${id}`, data);

export const deleteService = (id: string) =>
  api.delete(`/served/services/${id}`);

export const getCustomers = (params?: { date?: string; search?: string }) =>
  api.get<{ data: ServedCustomer[] }>('/served/customers', { params });

export const createCustomer = (data: {
  name: string; phone?: string; served_date: string;
  notes?: string; service_ids?: string[];
}) => api.post<{ data: ServedCustomer }>('/served/customers', data);

export const updateCustomer = (id: string, data: Partial<{
  name: string; phone: string; served_date: string;
  notes: string; service_ids: string[];
}>) => api.put<{ data: ServedCustomer }>(`/served/customers/${id}`, data);

export const deleteCustomer = (id: string) =>
  api.delete(`/served/customers/${id}`);

export const createFeedback = (customerId: string, data: {
  rating?: number; outcome?: string;
  feedback?: string; challenges?: string; internal_notes?: string;
}) => api.post<{ data: CustomerFeedback }>(`/served/customers/${customerId}/feedback`, data);

export const deleteFeedback = (customerId: string, feedbackId: string) =>
  api.delete(`/served/customers/${customerId}/feedback/${feedbackId}`);

// ── Targets ──────────────────────────────────────────────────────────────────

export interface ServedTarget {
  id:                      string;
  new_customers_target:    number;
  called_customers_target: number;
  active_days:             number[];
  effective_from:          string;
}

export interface ServedDailyBreakdown {
  date:           string;
  day_name:       string;
  is_active:      boolean;
  new_customers:  number;
  calls_made:     number;
}

export interface ServedWeeklySummary {
  week_start:              string;
  week_end:                string;
  target:                  ServedTarget | null;
  new_customers_achieved:  number;
  calls_achieved:          number;
  new_customers_target:    number | null;
  calls_target:            number | null;
  daily:                   ServedDailyBreakdown[];
}

export const getServedTarget = () =>
  api.get<{ data: ServedTarget | null }>('/served/target');

export const upsertServedTarget = (data: {
  new_customers_target: number; called_customers_target: number;
  active_days: number[]; effective_from: string;
}) => api.post<{ data: ServedTarget }>('/served/target', data);

export const getServedWeeklySummary = (weekStart: string) =>
  api.get<ServedWeeklySummary>('/served/weekly-summary', { params: { week_start: weekStart } });

export interface ServedReportDay {
  date:          string;
  day_name:      string;
  week:          number;
  is_active:     boolean;
  new_customers: number;
  new_target:    number;
  new_pct:       number | null;
  calls_made:    number;
  calls_target:  number;
  calls_pct:     number | null;
}

export interface ServedReport {
  start_date:              string;
  end_date:                string;
  target:                  ServedTarget | null;
  new_customers_achieved:  number;
  new_customers_target:    number;
  calls_achieved:          number;
  calls_target:            number;
  daily:                   ServedReportDay[];
}

export const getServedReport = (startDate: string, endDate: string) =>
  api.get<ServedReport>('/served/report', { params: { start_date: startDate, end_date: endDate } });
