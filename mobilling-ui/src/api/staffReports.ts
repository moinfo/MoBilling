import api from './axios';

export interface StaffReport {
  id:           string;
  user:         { id: string; name: string };
  report_type:  'daily' | 'weekly' | 'monthly';
  period_date:  string;
  period_label: string;
  achievements: string | null;
  challenges:   string | null;
  plans:        string | null;
  notes:        string | null;
  status:       'submitted' | 'reviewed';
  reviewer:     { id: string; name: string } | null;
  reviewed_at:  string | null;
  review_notes: string | null;
  rating:       number | null;
  created_at:   string;
}

export const getReports = (params?: {
  report_type?: string; user_id?: string; status?: string;
}) => api.get<{ data: StaffReport[] }>('/staff-reports', { params });

export const createReport = (data: {
  report_type: string; period_date: string;
  achievements?: string; challenges?: string; plans?: string; notes?: string;
}) => api.post<{ data: StaffReport }>('/staff-reports', data);

export const updateReport = (id: string, data: {
  achievements?: string; challenges?: string; plans?: string; notes?: string;
}) => api.put<{ data: StaffReport }>(`/staff-reports/${id}`, data);

export const deleteReport = (id: string) =>
  api.delete(`/staff-reports/${id}`);

export const reviewReport = (id: string, data: {
  rating?: number; review_notes?: string;
}) => api.post<{ data: StaffReport }>(`/staff-reports/${id}/review`, data);
