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
  client: { id: string; name: string } | null;
  channel: 'email' | 'sms' | 'whatsapp';
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

export interface UpcomingReminderEvent {
  date: string;
  client_id: string;
  client_name: string;
  category: string;
  label: string;
  reference: string;
  channels: ('email' | 'sms' | 'whatsapp')[];
  recipient_email: string | null;
  recipient_phone: string | null;
}

export const getUpcomingReminders = (days?: number) =>
  api.get<{ data: UpcomingReminderEvent[] }>('/automation/upcoming-reminders', { params: { days } });

export const exportUpcomingReminders = (days: number, format: 'pdf' | 'csv') =>
  api.get('/automation/upcoming-reminders/export', { params: { days, format }, responseType: 'blob' });

export const getCommunicationLogs = (params?: {
  date?: string;
  search?: string;
  client_only?: boolean;
  channel?: string;
  type?: string;
  status?: string;
  page?: number;
  per_page?: number;
}) =>
  api.get<{ data: CommunicationLogEntry[]; meta: { last_page: number } }>('/automation/communication-logs', { params });
