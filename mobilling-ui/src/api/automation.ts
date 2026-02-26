import api from './axios';

export interface AutomationSummary {
  date: string;
  invoices_created: number;
  reminders_sent: number;
  bills_generated: number;
  subscriptions_expired: number;
  emails_sent: number;
  sms_sent: number;
  failed_communications: number;
}

export interface CronLogEntry {
  id: string;
  tenant_id: string | null;
  command: string;
  description: string;
  results: Record<string, number> | null;
  status: 'success' | 'failed';
  error: string | null;
  started_at: string;
  finished_at: string | null;
  created_at: string;
}

export interface CommunicationLogEntry {
  id: string;
  client_id: string | null;
  channel: 'email' | 'sms';
  type: string;
  recipient: string;
  subject: string | null;
  message: string | null;
  status: 'sent' | 'failed';
  error: string | null;
  metadata: Record<string, string> | null;
  created_at: string;
}

export const getAutomationSummary = (date?: string) =>
  api.get<{ data: AutomationSummary }>('/automation/summary', { params: { date } });

export const getCronLogs = (params?: { date?: string; page?: number; per_page?: number }) =>
  api.get<{ data: CronLogEntry[]; meta: { last_page: number } }>('/automation/cron-logs', { params });

export const getCommunicationLogs = (params?: {
  date?: string;
  channel?: string;
  type?: string;
  status?: string;
  page?: number;
  per_page?: number;
}) =>
  api.get<{ data: CommunicationLogEntry[]; meta: { last_page: number } }>('/automation/communication-logs', { params });
