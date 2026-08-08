import api from './axios';

export interface SessionRow {
  id: number;
  token_name: string;
  owner_type: 'staff' | 'client';
  owner_id: string;
  owner_name: string;
  owner_email: string | null;
  owner_active: boolean;
  client_name: string | null;
  client_status: string | null;
  effectively_active: boolean;
  last_used_at: string | null;
  created_at: string;
  never_used: boolean;
}

export interface SessionsSummary {
  total: number;
  never_used: number;
  on_inactive: number;
}

export const getSessions = (params?: { type?: 'staff' | 'client'; status?: 0 | 1; search?: string }) =>
  api.get<{ data: SessionRow[]; summary: SessionsSummary }>('/sessions', { params });

export const revokeSession = (id: number) =>
  api.delete<{ message: string }>(`/sessions/${id}`);

export const revokeInactiveSessions = (includeNeverUsed: boolean) =>
  api.post<{ message: string }>('/sessions/revoke-inactive', { include_never_used: includeNeverUsed });
