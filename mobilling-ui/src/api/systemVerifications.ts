import api from './axios';

export interface SystemVerificationTodayReport {
  id: string;
  status: 'ok' | 'issue';
  notes: string | null;
  submitted_at: string;
}

export interface SystemVerification {
  id: string;
  name: string;
  domain_name: string | null;
  client_id: string | null;
  client?: { id: string; name: string; email: string | null };
  is_active: boolean;
  assigned_user_id: string | null;
  assigned_user?: { id: string; name: string };
  todays_report?: SystemVerificationTodayReport;
  created_at: string;
}

export interface SystemVerificationPayload {
  name: string;
  domain_name?: string | null;
  client_id?: string | null;
  assigned_user_id?: string | null;
  is_active?: boolean;
}

export interface SystemVerificationReport {
  id: string;
  system_verification_id: string;
  system?: { id: string; name: string; domain_name: string | null };
  user_id: string;
  user?: { id: string; name: string };
  report_date: string;
  status: 'ok' | 'issue';
  notes: string | null;
  created_at: string;
}

export interface SubmitReportPayload {
  status: 'ok' | 'issue';
  notes?: string;
}

// Admin endpoints
export const getSystemVerifications = (params?: { search?: string; page?: number; per_page?: number }) =>
  api.get('/system-verifications', { params });

export const createSystemVerification = (data: SystemVerificationPayload) =>
  api.post('/system-verifications', data);

export const updateSystemVerification = (id: string, data: SystemVerificationPayload) =>
  api.put(`/system-verifications/${id}`, data);

export const deleteSystemVerification = (id: string) =>
  api.delete(`/system-verifications/${id}`);

export const getSystemVerificationReports = (id: string, params?: { date_from?: string; date_to?: string; page?: number; per_page?: number }) =>
  api.get(`/system-verifications/${id}/reports`, { params });

// Staff endpoints
export const getMyVerifications = () =>
  api.get('/my-verifications');

export const submitVerificationReport = (id: string, data: SubmitReportPayload) =>
  api.post(`/system-verifications/${id}/reports`, data);
