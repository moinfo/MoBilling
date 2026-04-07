import api from './axios';

// ── Constants ────────────────────────────────────────────────

export const SERVICES = [
  'MoBilling',
  'Bulk SMS',
  'Hosting',
  'Web Design',
  'CCTV',
  'POS System',
  'E-File System',
  'IT Support',
  'Online Marketing',
  'Other',
] as const;

export const VISIT_STATUSES = [
  { value: 'interested',      label: 'Interested',      color: 'blue'  },
  { value: 'not_interested',  label: 'Not Interested',  color: 'gray'  },
  { value: 'follow_up',       label: 'Follow Up',       color: 'yellow'},
  { value: 'converted',       label: 'Converted',       color: 'green' },
] as const;

export type VisitStatus = 'interested' | 'not_interested' | 'follow_up' | 'converted';

// ── Types ────────────────────────────────────────────────────

export interface FieldSession {
  id: string;
  officer: { id: string; name: string };
  visit_date: string;
  area: string;
  summary: string | null;
  challenges: string | null;
  recommendations: string | null;
  visits_count: number;
  interested_count: number;
  converted_count: number;
  created_at: string;
}

export interface FieldVisit {
  id: string;
  session_id: string;
  officer_id: string;
  business_name: string;
  location: string;
  phone: string | null;
  services: string[];
  feedback: string | null;
  status: VisitStatus;
  client_id: string | null;
  client: { id: string; name: string } | null;
  created_at: string;
}

export interface FieldTarget {
  id: string;
  officer: { id: string; name: string };
  month: number;
  year: number;
  target_clients: number;
  won_clients: number;
  total_visits: number;
  progress: number;
}

export interface FieldStats {
  total_visits: number;
  total_converted: number;
  by_status: Record<string, number>;
  by_officer: { officer_id: string; visits: number; won: number; officer: { id: string; name: string } }[];
}

// ── Sessions ─────────────────────────────────────────────────

export const getSessions = (params?: { officer_id?: string; month?: number; year?: number }) =>
  api.get<FieldSession[]>('/field-sessions', { params }).then(r => r.data);

export const getSessionDetail = (sessionId: string) =>
  api.get<{ session: FieldSession; visits: FieldVisit[] }>(`/field-sessions/${sessionId}`).then(r => r.data);

export const createSession = (data: {
  officer_id: string;
  visit_date: string;
  area: string;
  summary?: string;
  challenges?: string;
  recommendations?: string;
}) => api.post<FieldSession>('/field-sessions', data).then(r => r.data);

export const updateSession = (id: string, data: Partial<Parameters<typeof createSession>[0]>) =>
  api.put<FieldSession>(`/field-sessions/${id}`, data).then(r => r.data);

export const deleteSession = (id: string) =>
  api.delete(`/field-sessions/${id}`);

// ── Visits ───────────────────────────────────────────────────

export const createVisit = (sessionId: string, data: {
  business_name: string;
  location: string;
  phone?: string;
  services: string[];
  feedback?: string;
  status: VisitStatus;
}) => api.post<FieldVisit>(`/field-sessions/${sessionId}/visits`, data).then(r => r.data);

export const updateVisit = (sessionId: string, visitId: string, data: {
  business_name?: string;
  location?: string;
  phone?: string;
  services?: string[];
  feedback?: string;
  status?: VisitStatus;
  client_id?: string | null;
}) => api.put<FieldVisit>(`/field-sessions/${sessionId}/visits/${visitId}`, data).then(r => r.data);

export const deleteVisit = (sessionId: string, visitId: string) =>
  api.delete(`/field-sessions/${sessionId}/visits/${visitId}`);

export const convertVisit = (sessionId: string, visitId: string, data: {
  client_id?: string;
  client_name?: string;
  client_email?: string;
  client_phone?: string;
}) => api.post<FieldVisit>(`/field-sessions/${sessionId}/visits/${visitId}/convert`, data).then(r => r.data);

// ── Targets ──────────────────────────────────────────────────

export const getTargets = (month: number, year: number) =>
  api.get<FieldTarget[]>('/field-targets', { params: { month, year } }).then(r => r.data);

export const setTarget = (data: {
  officer_id: string;
  month: number;
  year: number;
  target_clients: number;
}) => api.post<FieldTarget>('/field-targets', data).then(r => r.data);

// ── Followups ────────────────────────────────────────────────

export type FollowupOutcome = 'answered' | 'no_answer' | 'callback' | 'interested' | 'not_interested' | 'converted';

export const OUTCOME_META: Record<FollowupOutcome, { label: string; color: string }> = {
  answered:        { label: 'Answered',       color: 'blue'   },
  no_answer:       { label: 'No Answer',      color: 'gray'   },
  callback:        { label: 'Callback',       color: 'yellow' },
  interested:      { label: 'Interested',     color: 'teal'   },
  not_interested:  { label: 'Not Interested', color: 'red'    },
  converted:       { label: 'Converted',      color: 'green'  },
};

export interface FieldFollowup {
  id: string;
  visit_id: string;
  user_id: string;
  user: { id: string; name: string };
  call_date: string;
  outcome: FollowupOutcome;
  notes: string | null;
  next_followup_date: string | null;
  created_at: string;
}

export const getFollowups = (visitId: string) =>
  api.get<FieldFollowup[]>(`/field-visits/${visitId}/followups`).then(r => r.data);

export const createFollowup = (visitId: string, data: {
  call_date: string;
  outcome: FollowupOutcome;
  notes?: string;
  next_followup_date?: string;
}) => api.post<FieldFollowup>(`/field-visits/${visitId}/followups`, data).then(r => r.data);

export const deleteFollowup = (visitId: string, followupId: string) =>
  api.delete(`/field-visits/${visitId}/followups/${followupId}`);

// ── Stats ────────────────────────────────────────────────────

export const getFieldStats = (month: number, year: number) =>
  api.get<FieldStats>('/field-stats', { params: { month, year } }).then(r => r.data);
