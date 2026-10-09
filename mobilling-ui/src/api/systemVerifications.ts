import api from './axios';

export interface VerificationFieldDef { key: string; label: string }

// The four built-in daily closing figures — mirrors
// SystemVerification::AVAILABLE_FIELDS on the backend. Beyond these, a
// tenant admin can add their own via getVerificationFields() below; combine
// both lists (built-ins first) wherever "which fields exist" is needed.
export const VERIFICATION_FIELD_DEFS: VerificationFieldDef[] = [
  { key: 'cash', label: 'Cash' },
  { key: 'sales', label: 'Sales' },
  { key: 'credit', label: 'Credit' },
  { key: 'gain_loss', label: 'Gain / Loss' },
];
export const BUILT_IN_FIELD_KEYS = VERIFICATION_FIELD_DEFS.map((f) => f.key);

export interface VerificationFieldDefinition {
  id: string;
  key: string;
  label: string;
}

export interface SystemVerificationTodayReport {
  id: string;
  status: 'ok' | 'issue';
  notes: string | null;
  cash: string | null;
  sales: string | null;
  credit: string | null;
  gain_loss: string | null;
  custom_values: Record<string, string | number | null>;
  submitted_on_time: boolean | null;
  submitted_at: string;
}

export interface SystemVerification {
  id: string;
  name: string;
  domain_name: string | null;
  client_id: string | null;
  client?: { id: string; name: string; email: string | null };
  login_username: string | null;
  login_password: string | null;
  // This system's OWN daily check-in window — each assigned person (and
  // each system) can have a different one, not one rule for the tenant.
  window_from: string | null;
  window_to: string | null;
  // Resolved by the backend — never null; a system created before this
  // setting existed reports all four (SystemVerification::requiredFields()).
  required_fields: string[];
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
  login_username?: string | null;
  login_password?: string | null;
  window_from?: string | null;
  window_to?: string | null;
  assigned_user_id?: string | null;
  is_active?: boolean;
  required_fields?: string[] | null;
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
  cash: string | null;
  sales: string | null;
  credit: string | null;
  gain_loss: string | null;
  custom_values: Record<string, string | number | null>;
  submitted_on_time: boolean | null;
  created_at: string;
}

export interface SubmitReportPayload {
  status: 'ok' | 'issue';
  notes?: string;
  // Only fields this system's required_fields asks for are expected to be
  // sent; the others are simply omitted rather than forced to 0.
  cash?: number;
  sales?: number;
  credit?: number;
  gain_loss?: number;
  // Values for admin-defined custom fields, keyed by their `key`.
  custom_values?: Record<string, number>;
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

// Custom field definitions (admin-added, beyond the four built-in figures)
export const getVerificationFields = () =>
  api.get('/system-verification-fields');

export const createVerificationField = (label: string) =>
  api.post('/system-verification-fields', { label });

export const updateVerificationField = (id: string, label: string) =>
  api.put(`/system-verification-fields/${id}`, { label });

export const deleteVerificationField = (id: string) =>
  api.delete(`/system-verification-fields/${id}`);
