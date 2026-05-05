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
  is_late:      boolean;
  reviewer:     { id: string; name: string } | null;
  reviewed_at:  string | null;
  review_notes: string | null;
  rating:       number | null;
  created_at:   string;
}

export interface ReportSettings {
  daily_target:          number;
  weekly_target:         number;
  monthly_target:        number;
  daily_deadline_time:   string;
  weekly_deadline_day:   number;
  weekly_deadline_time:  string;
  monthly_deadline_day:  number;
  monthly_deadline_time: string;
}

export interface MonthStats {
  submitted: number;
  reviewed:  number;
  late:      number;
  target:    number;
}

export interface StaffStat {
  user: { id: string; name: string };
  daily:   MonthStats;
  weekly:  MonthStats;
  monthly: MonthStats;
}

export interface DashboardData {
  this_month: { daily: MonthStats; weekly: MonthStats; monthly: MonthStats };
  recent_reviews: StaffReport[];
  settings: ReportSettings;
  team: { pending_review: number; staff: StaffStat[] } | null;
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

export const getDashboard = () =>
  api.get<{ data: DashboardData }>('/staff-reports/dashboard');

export const getSettings = () =>
  api.get<{ data: ReportSettings }>('/staff-reports/settings');

export const updateSettings = (data: ReportSettings) =>
  api.put<{ data: ReportSettings }>('/staff-reports/settings', data);

export interface StaffWithSupervisor {
  id:         string;
  name:       string;
  supervisor: { id: string; name: string } | null;
}

export const getSupervisors = () =>
  api.get<{ data: StaffWithSupervisor[] }>('/staff-reports/supervisors');

export const updateSupervisor = (userId: string, supervisorId: string | null) =>
  api.put<{ data: StaffWithSupervisor }>(`/staff-reports/supervisors/${userId}`, {
    supervisor_id: supervisorId,
  });
